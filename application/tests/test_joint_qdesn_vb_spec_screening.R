repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN screening test.", call. = FALSE)
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

worker_probe <- app_joint_qdesn_parallel_lapply(
  c("ok_scenario", "bad_scenario"),
  function(scenario_id) {
    if (identical(scenario_id, "bad_scenario")) stop("intentional worker probe", call. = FALSE)
    list(status = "ok")
  },
  n_cores = 1L
)
stopifnot(!app_joint_qdesn_is_worker_error(worker_probe[[1L]]))
stopifnot(app_joint_qdesn_is_worker_error(worker_probe[[2L]]))
worker_failures <- app_joint_qdesn_worker_failure_rows(worker_probe, "fit")
stopifnot(nrow(worker_failures) == 1L)
stopifnot(worker_failures$scenario_id[[1L]] == "bad_scenario")
stopifnot(grepl("intentional worker probe", worker_failures$error_message[[1L]], fixed = TRUE))

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

toy <- app_joint_qdesn_vb_readiness_fixture(
  Tn = 28L,
  washout_length = 6L,
  tau = c(0.1, 0.5, 0.9),
  seed = 2026070606L
)
controls <- list(
  vb_max_iter = 2L,
  vb_tol = 1.0e-4,
  rhs_vb_inner = 1L,
  tau0 = 0.5,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = 0.5,
  alpha_min_spacing = 0,
  max_dense_dim = 300L
)
joint_al <- app_joint_qdesn_fit_joint_al_readiness(toy, controls)
joint_exal <- app_joint_qdesn_fit_joint_exal_readiness(toy, controls, init = joint_al)
stopifnot(!is.null(joint_exal$alpha_prior_sd))
stopifnot(all(abs(joint_exal$alpha_prior_sd - 0.5) < 1.0e-12))
stopifnot(identical(joint_exal$alpha_prior_mean_source, "empirical_quantile"))

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
small$seed <- 202607232L
app_joint_qdesn_validate_simulation_registry(small)

fixture_dir <- tempfile("joint_qdesn_screening_fixture_")
fixture <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = fixture_dir,
  registry = small,
  registry_path = app_joint_qdesn_default_simulation_registry_path()
)
stopifnot(all(fixture$fixture_validation$status == "pass"))
check_manifest(fixture$out_dir)

screen_dir <- tempfile("joint_qdesn_vb_spec_screening_")
candidates <- app_joint_qdesn_default_vb_spec_screening_registry(out_dir = screen_dir, n_cores = 1L)
candidates <- candidates[candidates$candidate_id == "rhs_tau0_0p5_alpha0p5", , drop = FALSE]
candidates$candidate_id <- "tiny_rhs_tau0_0p5_alpha0p5"
candidates$candidate_label <- "Tiny RHS tau0 0.5 alpha sd 0.5"
candidates$fit_dir <- file.path(screen_dir, "candidates", candidates$candidate_id, "fit")
candidates$forecast_dir <- file.path(screen_dir, "candidates", candidates$candidate_id, "forecast")
candidates$vb_max_iter <- 1L
candidates$adaptive_vb_max_iter_grid <- "1"
candidates$rhs_vb_inner <- 1L
candidates$n_cores <- 1L
app_joint_qdesn_validate_screening_registry(candidates)

result <- app_joint_qdesn_run_vb_spec_screening(
  out_dir = screen_dir,
  fixture_dir = fixture$out_dir,
  candidate_registry = candidates,
  n_cores = 1L,
  reuse_completed = FALSE,
  catastrophic_truth_mae = 5
)

check_manifest(result$out_dir)
fit_failure <- utils::read.csv(file.path(candidates$fit_dir[[1L]], "scenario_failure.csv"), stringsAsFactors = FALSE)
forecast_failure <- utils::read.csv(file.path(candidates$forecast_dir[[1L]], "scenario_failure.csv"), stringsAsFactors = FALSE)
failure_summary <- utils::read.csv(file.path(result$out_dir, "scenario_failure_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_failure) == 0L)
stopifnot(nrow(forecast_failure) == 0L)
stopifnot(nrow(failure_summary) == 0L)
stopifnot(nrow(result$health) == 1L)
stopifnot(result$health$candidate_id[[1L]] == "tiny_rhs_tau0_0p5_alpha0p5")
stopifnot(result$health$fit_models[[1L]] == 4L)
stopifnot(result$health$forecast_models[[1L]] == 4L)
stopifnot(all(result$manifest_verification$status == "pass"))
stopifnot(file.exists(file.path(result$out_dir, "candidate_registry.csv")))
stopifnot(file.exists(file.path(result$out_dir, "candidate_scorecard.csv")))
stopifnot(file.exists(file.path(result$out_dir, "selected_spec_recommendation.csv")))

fit_model <- utils::read.csv(file.path(result$out_dir, "fit_model_metric_summary.csv"), stringsAsFactors = FALSE)
forecast_model <- utils::read.csv(file.path(result$out_dir, "forecast_model_metric_summary.csv"), stringsAsFactors = FALSE)
forecast_tau <- utils::read.csv(file.path(result$out_dir, "forecast_tau_metric_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_model) == 4L)
stopifnot(nrow(forecast_model) == 4L)
stopifnot(all(is.finite(fit_model$truth_mae)))
stopifnot(all(is.finite(forecast_model$truth_mae)))
stopifnot(all(forecast_model$contract_crossing_pairs == 0L))
stopifnot(nrow(forecast_tau) == 4L * 7L)
