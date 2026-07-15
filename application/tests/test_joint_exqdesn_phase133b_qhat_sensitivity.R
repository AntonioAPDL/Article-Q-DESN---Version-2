repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase133B test.", call. = FALSE)
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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase133b_qhat_sensitivity.R"))

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

tau <- c(0.05, 0.50, 0.95)
Z <- cbind(1, seq_len(4) / 10)
make_fit <- function(offset) {
  list(
    beta_draws = matrix(seq(0.1 + offset, 1.2 + offset, length.out = 36), nrow = 6),
    alpha_draws = matrix(seq(-0.3 + offset, 0.3 + offset, length.out = 18), nrow = 6)
  )
}
fits <- list(make_fit(0), make_fit(0.2))
plan <- app_joint_exqdesn_qhat_draw_plan(fits, max_draws = 5L, seed = 123L)
plan_again <- app_joint_exqdesn_qhat_draw_plan(fits, max_draws = 5L, seed = 123L)
stopifnot(identical(plan[, c("chain_id", "draw_index")], plan_again[, c("chain_id", "draw_index")]))
stopifnot(nrow(plan) == 5L)

summary <- app_joint_exqdesn_qhat_summary_matrix(fits, Z, tau, plan, trim_fraction = 0.10)
stopifnot(identical(dim(summary$mean), c(4L, 3L)))
stopifnot(identical(dim(summary$median), c(4L, 3L)))
stopifnot(identical(dim(summary$trimmed_mean), c(4L, 3L)))
stopifnot(isTRUE(summary$finite))
stopifnot(summary$n_draws_used == 5L)

meta <- data.frame(
  scenario_id = "unit_case",
  model_id = "joint_exqdesn_rhs_mcmc",
  display_label = "Joint exQDESN RHS MCMC",
  likelihood = "exal",
  fit_structure = "joint",
  stringsAsFactors = FALSE
)
fixture_like <- list(
  tau = tau,
  y = c(-1, 0, 1, 2),
  true_q = matrix(c(-2, -1, 0, -1, 0, 1, 0, 1, 2, 1, 2, 3), nrow = 4, byrow = TRUE),
  row_meta = data.frame(full_time_index = 1:4, validation_role = "fit", stringsAsFactors = FALSE)
)
scored <- app_joint_exqdesn_score_summary_family(meta, fixture_like, summary, "mcmc_posterior_qhat", "fit")
stopifnot(identical(sort(unique(scored$scored$qhat_summary_method)), c("mean", "median", "trimmed_mean")))
truth <- app_joint_exqdesn_phase133b_summary_by_qhat_method(scored$scored, app_joint_qdesn_truth_summary)
stopifnot("qhat_summary_method" %in% names(truth))
stopifnot(identical(sort(unique(truth$qhat_summary_method)), c("mean", "median", "trimmed_mean")))
stopifnot(all(is.finite(truth$truth_mae)))
stopifnot(sum(scored$contract_crossing$n_crossing_pairs, na.rm = TRUE) == 0L)

registry <- app_joint_qdesn_load_simulation_registry()
small <- registry[registry$scenario_id == "normal_bridge", , drop = FALSE]
small$simulated_length <- 48L
small$dgp_warmup_length <- 8L
small$effective_length <- 40L
small$analysis_window_length <- 20L
small$desn_washout_length <- 5L
small$train_length <- 7L
small$fit_length <- 7L
small$test_length <- 8L
small$validation_length <- 8L
small$washout_length <- small$dgp_warmup_length + (small$effective_length - small$analysis_window_length) + small$desn_washout_length
small$forecast_origin_stride <- 4L
small$max_lead <- 4L
small$seed <- 202607245L
app_joint_qdesn_validate_simulation_registry(small)

fixture_dir <- tempfile("joint_exqdesn_phase133b_fixture_")
fixture <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = fixture_dir,
  registry = small,
  registry_path = app_joint_qdesn_default_simulation_registry_path()
)
stopifnot(all(fixture$fixture_validation$status == "pass"))
check_manifest(fixture$out_dir)

phase121_dir <- tempfile("joint_exqdesn_phase133b_phase121_")
app_ensure_dir(phase121_dir)
controls <- data.frame(
  case_id = "normal_bridge__joint_exqdesn_rhs_vb",
  scenario_ids = "normal_bridge",
  model_ids = "joint_exqdesn_rhs_vb",
  candidate_id = "phase133b_test_candidate",
  phase121_selection_status = "test_selected",
  vb_max_iter = 1L,
  adaptive_vb_max_iter_grid = "1",
  vb_tol = 1.0e-3,
  rhs_vb_inner = 1L,
  tau0 = 0.50,
  zeta2 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = "0.5",
  alpha_min_spacing = 0,
  gamma_init_policy = "zero",
  review_adjustment_threshold = 1.0e-3,
  max_dense_dim = 300L,
  stringsAsFactors = FALSE
)
metric <- data.frame(case_id = controls$case_id, scenario_id = controls$scenario_ids, model_id = controls$model_ids, gate_status = "review", stringsAsFactors = FALSE)
gate <- data.frame(case_id = controls$case_id, gate_status = "review", gate_reason = "tiny test fixture", stringsAsFactors = FALSE)
controls_path <- app_joint_qvp_write_csv(controls, file.path(phase121_dir, "case_winner_controls.csv"))
metric_path <- app_joint_qvp_write_csv(metric, file.path(phase121_dir, "case_winner_metric_summary.csv"))
gate_path <- app_joint_qvp_write_csv(gate, file.path(phase121_dir, "case_winner_gate_audit.csv"))
app_joint_qdesn_write_manifest(c(
  case_winner_controls = controls_path,
  case_winner_metric_summary = metric_path,
  case_winner_gate_audit = gate_path
), phase121_dir)
check_manifest(phase121_dir)

phase133_dir <- tempfile("joint_exqdesn_phase133b_phase133_")
app_ensure_dir(phase133_dir)
priority <- data.frame(
  scenario_id = "normal_bridge",
  performance_priority = "high",
  mcmc_forecast_truth_mae = 1.00,
  forecast_mae_winner = "Joint QDESN RHS MCMC",
  forecast_mae_winner_value = 0.90,
  forecast_mae_gap_to_best = 0.10,
  sampler_priority = "medium",
  stringsAsFactors = FALSE
)
priority_path <- app_joint_qvp_write_csv(priority, file.path(phase133_dir, "joint_exqdesn_scenario_priority_table.csv"))
readme_path <- file.path(phase133_dir, "README.md")
writeLines("# tiny Phase133 source for Phase133B test", readme_path)
app_joint_qdesn_write_manifest(c(
  joint_exqdesn_scenario_priority_table = priority_path,
  readme = readme_path
), phase133_dir)
check_manifest(phase133_dir)

out_dir <- tempfile("joint_exqdesn_phase133b_out_")
result <- app_joint_exqdesn_run_phase133b_qhat_sensitivity(
  out_dir = out_dir,
  phase133_dir = phase133_dir,
  phase121_dir = phase121_dir,
  fixture_dir = fixture$out_dir,
  scenario_ids = "normal_bridge",
  model_ids = "joint_exqdesn_rhs_vb",
  n_chains = 2L,
  mcmc_n_iter = 12L,
  mcmc_burn = 6L,
  mcmc_thin = 3L,
  n_cores = 1L,
  qhat_max_draws = 4L
)
manifest <- check_manifest(result$out_dir)
expected_labels <- c(
  "run_config",
  "source_manifest_verification",
  "posterior_qhat_draw_sampling_plan",
  "posterior_qhat_summary_fit_raw",
  "posterior_qhat_summary_fit",
  "posterior_qhat_summary_fit_adjustment",
  "posterior_qhat_summary_fit_uncertainty",
  "posterior_qhat_summary_forecast_raw",
  "posterior_qhat_summary_forecast",
  "posterior_qhat_summary_forecast_adjustment",
  "posterior_qhat_summary_forecast_uncertainty",
  "posterior_qhat_summary_fit_crossing",
  "posterior_qhat_summary_forecast_crossing",
  "posterior_qhat_summary_fit_raw_crossing",
  "posterior_qhat_summary_forecast_raw_crossing",
  "posterior_qhat_summary_method_metrics",
  "fit_truth_distance_summary",
  "forecast_truth_distance_summary",
  "fit_check_loss_summary",
  "forecast_check_loss_summary",
  "fit_hit_rate_summary",
  "forecast_hit_rate_summary",
  "fit_crps_grid_summary",
  "forecast_crps_grid_summary",
  "fit_interval_summary",
  "forecast_interval_summary",
  "qhat_summary_method_recommendation",
  "vb_convergence_audit",
  "objective_diagnostics",
  "mcmc_draw_summary",
  "vb_mcmc_distance_summary",
  "chain_to_pooled_distance_summary",
  "runtime_summary",
  "audit_assessment",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected_labels))
stopifnot(result$assessment$implementation_gate[[1L]] == "pass")
stopifnot(nrow(result$worker_failures) == 0L)

method_metrics <- utils::read.csv(file.path(result$out_dir, "posterior_qhat_summary_method_metrics.csv"), stringsAsFactors = FALSE)
forecast_truth <- utils::read.csv(file.path(result$out_dir, "forecast_truth_distance_summary.csv"), stringsAsFactors = FALSE)
forecast_scored <- utils::read.csv(file.path(result$out_dir, "posterior_qhat_summary_forecast.csv"), stringsAsFactors = FALSE)
forecast_raw <- utils::read.csv(file.path(result$out_dir, "posterior_qhat_summary_forecast_raw.csv"), stringsAsFactors = FALSE)
forecast_crossing <- utils::read.csv(file.path(result$out_dir, "posterior_qhat_summary_forecast_crossing.csv"), stringsAsFactors = FALSE)
source_manifest <- utils::read.csv(file.path(result$out_dir, "source_manifest_verification.csv"), stringsAsFactors = FALSE)
draw_plan <- utils::read.csv(file.path(result$out_dir, "posterior_qhat_draw_sampling_plan.csv"), stringsAsFactors = FALSE)

stopifnot(identical(sort(unique(method_metrics$qhat_summary_method)), c("mean", "median", "trimmed_mean")))
stopifnot(identical(sort(unique(forecast_truth$qhat_summary_method)), c("mean", "median", "trimmed_mean")))
stopifnot(identical(sort(unique(forecast_scored$qhat_summary_method)), c("mean", "median", "trimmed_mean")))
stopifnot("qhat_raw" %in% names(forecast_raw))
stopifnot(all(is.finite(method_metrics$forecast_truth_mae)))
stopifnot(sum(forecast_crossing$n_crossing_pairs, na.rm = TRUE) == 0L)
stopifnot(all(source_manifest$status == "pass"))
stopifnot(all(draw_plan$n_available_draws_total == 4L))

cat("joint_exqdesn_phase133b_qhat_sensitivity tests passed\n")
