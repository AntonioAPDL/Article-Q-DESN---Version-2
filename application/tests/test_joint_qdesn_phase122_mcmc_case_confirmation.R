repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 122 test.", call. = FALSE)
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
small$seed <- 202607252L
app_joint_qdesn_validate_simulation_registry(small)

fixture_dir <- tempfile("joint_qdesn_phase122_fixture_")
fixture <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = fixture_dir,
  registry = small,
  registry_path = app_joint_qdesn_default_simulation_registry_path()
)
stopifnot(all(fixture$fixture_validation$status == "pass"))
invisible(check_manifest(fixture$out_dir))

phase121_dir <- tempfile("joint_qdesn_phase121_for_phase122_")
app_ensure_dir(phase121_dir)
specs <- app_joint_qdesn_simulation_model_specs()
controls <- data.frame(
  case_id = paste("normal_bridge", specs$model_id, sep = "__"),
  scenario_ids = "normal_bridge",
  model_ids = specs$model_id,
  candidate_id = paste("normal_bridge", specs$model_id, "phase122_test", sep = "__"),
  candidate_label = paste("Phase122 test", specs$display_label),
  source_shard = "phase122_test",
  phase121_selection_status = "pass",
  phase121_selection_rule = "test_fixture",
  phase121_freeze_role = "vb_winner_ready_for_mcmc_initialization",
  vb_max_iter = 1L,
  adaptive_vb_max_iter_grid = "1",
  vb_tol = 1.0e-4,
  rhs_vb_inner = 1L,
  tau0 = 0.5,
  zeta2 = 16,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = "0.5",
  alpha_min_spacing = 0,
  gamma_init_policy = "zero",
  review_adjustment_threshold = 1.0e-3,
  max_dense_dim = 300L,
  fit_dir = file.path(phase121_dir, "fit"),
  forecast_dir = file.path(phase121_dir, "forecast"),
  notes = "Phase122 regression fixture",
  stringsAsFactors = FALSE
)
metrics <- data.frame(
  case_id = controls$case_id,
  scenario_ids = controls$scenario_ids,
  model_ids = controls$model_ids,
  forecast_truth_mae = 0.1,
  fit_truth_mae = 0.1,
  phase121_selection_status = controls$phase121_selection_status,
  stringsAsFactors = FALSE
)
gate <- data.frame(
  gate = c("source_manifests_and_workers", "selected_contract_crossings", "mcmc_scope_readiness"),
  status = c("pass", "pass", "review"),
  detail = c("test", "test", "test"),
  stringsAsFactors = FALSE
)
paths <- c(
  case_winner_controls = app_joint_qvp_write_csv(controls, file.path(phase121_dir, "case_winner_controls.csv")),
  case_winner_metric_summary = app_joint_qvp_write_csv(metrics, file.path(phase121_dir, "case_winner_metric_summary.csv")),
  case_winner_gate_audit = app_joint_qvp_write_csv(gate, file.path(phase121_dir, "case_winner_gate_audit.csv"))
)
invisible(app_joint_qdesn_write_manifest(paths, phase121_dir))
invisible(check_manifest(phase121_dir))

out_dir <- tempfile("joint_qdesn_phase122_mcmc_")
result <- app_joint_qdesn_run_phase122_mcmc_case_confirmation(
  out_dir = out_dir,
  phase121_dir = phase121_dir,
  fixture_dir = fixture$out_dir,
  n_chains = 1L,
  mcmc_n_iter = 8L,
  mcmc_burn = 4L,
  mcmc_thin = 2L,
  n_cores = 1L
)

manifest <- check_manifest(result$out_dir)
expected <- c(
  "run_config",
  "phase121_source_manifest_verification",
  "fixture_source_manifest",
  "case_winner_controls",
  "scenario_worker_failures",
  "mcmc_case_summary",
  "mcmc_case_assessment",
  "fit_quantiles_raw",
  "fit_quantiles",
  "fit_monotone_adjustment",
  "fit_truth_comparison",
  "forecast_quantiles_raw",
  "forecast_quantiles",
  "forecast_monotone_adjustment",
  "forecast_truth_comparison",
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
  "crossing_summary",
  "raw_crossing_summary",
  "vb_convergence_audit",
  "objective_diagnostics",
  "rhs_prior_summary",
  "scale_parameter_summary",
  "mcmc_draw_summary",
  "vb_mcmc_distance_summary",
  "chain_to_pooled_distance_summary",
  "runtime_summary",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected))

summary <- utils::read.csv(file.path(result$out_dir, "mcmc_case_summary.csv"), stringsAsFactors = FALSE)
assessment <- utils::read.csv(file.path(result$out_dir, "mcmc_case_assessment.csv"), stringsAsFactors = FALSE)
draws <- utils::read.csv(file.path(result$out_dir, "mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
fit_q <- utils::read.csv(file.path(result$out_dir, "fit_quantiles.csv"), stringsAsFactors = FALSE)
forecast_q <- utils::read.csv(file.path(result$out_dir, "forecast_quantiles.csv"), stringsAsFactors = FALSE)
crossing <- utils::read.csv(file.path(result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
failures <- utils::read.csv(file.path(result$out_dir, "scenario_worker_failures.csv"), stringsAsFactors = FALSE)

stopifnot(nrow(summary) == 4L)
stopifnot(nrow(assessment) == 4L)
stopifnot(nrow(failures) == 0L)
stopifnot(all(summary$all_chain_init_source_provided))
stopifnot(all(summary$mcmc_draws_all_finite))
stopifnot(all(summary$mcmc_n_keep_total == 2L))
stopifnot(all(assessment$implementation_status == "pass"))
stopifnot(!any(assessment$gate_status == "fail"))
stopifnot(all(c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb", "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb") %in% summary$source_model_id))
stopifnot(all(c("alpha", "beta", "sigma", "gamma") %in% unique(draws$block)))
stopifnot(all(is.finite(fit_q$qhat)))
stopifnot(all(is.finite(forecast_q$qhat)))
stopifnot(sum(crossing$n_crossing_pairs, na.rm = TRUE) == 0L)
stopifnot(isFALSE(result$run_config$scalar_predictive_density_claim[[1L]]))

cat("Joint QDESN Phase 122 MCMC case-confirmation test passed.\n")
