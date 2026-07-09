repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN validation test.", call. = FALSE)
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
small$seed <- 202607231L
app_joint_qdesn_validate_simulation_registry(small)

fixture_dir <- tempfile("joint_qdesn_validation_fixture_")
fixture <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = fixture_dir,
  registry = small,
  registry_path = app_joint_qdesn_default_simulation_registry_path()
)
stopifnot(all(fixture$fixture_validation$status == "pass"))
check_manifest(fixture$out_dir)

fit_dir <- tempfile("joint_qdesn_fit_validation_")
fit <- app_joint_qdesn_run_vb_fit_validation(
  out_dir = fit_dir,
  fixture_dir = fixture$out_dir,
  vb_max_iter = 1L,
  adaptive_vb_max_iter_grid = 1L,
  rhs_vb_inner = 1L,
  n_cores = 1L
)
check_manifest(fit$out_dir)
stopifnot(nrow(fit$fit_validation_assessment) == 4L)
stopifnot(all(fit$fit_validation_assessment$gate_status %in% c("pass", "review", "fail")))
stopifnot(!any(fit$fit_validation_assessment$gate_status == "fail"))

fit_quantiles <- utils::read.csv(file.path(fit$out_dir, "fit_quantiles.csv"), stringsAsFactors = FALSE)
fit_raw <- utils::read.csv(file.path(fit$out_dir, "fit_quantiles_raw.csv"), stringsAsFactors = FALSE)
fit_adjustment <- utils::read.csv(file.path(fit$out_dir, "fit_monotone_adjustment.csv"), stringsAsFactors = FALSE)
fit_crossing <- utils::read.csv(file.path(fit$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
fit_source <- utils::read.csv(file.path(fit$out_dir, "fixture_source_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(fit_source$status == "pass"))
stopifnot(all(fit_quantiles$role == "fit"))
stopifnot(nrow(fit_quantiles) == 4L * small$fit_length[[1L]] * 7L)
stopifnot(nrow(fit_raw) == nrow(fit_quantiles))
stopifnot(nrow(fit_adjustment) == nrow(fit_quantiles))
stopifnot(all(is.finite(fit_quantiles$qhat)))
stopifnot(all(is.finite(fit_quantiles$check_loss)))
stopifnot(all(fit_crossing$n_crossing_pairs == 0L))

forecast_dir <- tempfile("joint_qdesn_forecast_validation_")
forecast <- app_joint_qdesn_run_vb_forecast_validation(
  out_dir = forecast_dir,
  fixture_dir = fixture$out_dir,
  vb_max_iter = 1L,
  adaptive_vb_max_iter_grid = 1L,
  rhs_vb_inner = 1L,
  n_cores = 1L
)
check_manifest(forecast$out_dir)
stopifnot(nrow(forecast$forecast_validation_assessment) == 4L)
stopifnot(all(forecast$forecast_validation_assessment$gate_status %in% c("pass", "review", "fail")))
stopifnot(!any(forecast$forecast_validation_assessment$gate_status == "fail"))

forecast_quantiles <- utils::read.csv(file.path(forecast$out_dir, "forecast_quantiles.csv"), stringsAsFactors = FALSE)
forecast_raw <- utils::read.csv(file.path(forecast$out_dir, "forecast_quantiles_raw.csv"), stringsAsFactors = FALSE)
forecast_adjustment <- utils::read.csv(file.path(forecast$out_dir, "forecast_monotone_adjustment.csv"), stringsAsFactors = FALSE)
forecast_crossing <- utils::read.csv(file.path(forecast$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
forecast_origin_plan <- utils::read.csv(file.path(forecast$out_dir, "forecast_origin_plan.csv"), stringsAsFactors = FALSE)
forecast_source <- utils::read.csv(file.path(forecast$out_dir, "fixture_source_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(forecast_source$status == "pass"))
stopifnot(all(forecast_quantiles$role == "validation"))
stopifnot(nrow(forecast_origin_plan) == 2L)
stopifnot(nrow(forecast_quantiles) == 4L * nrow(forecast_origin_plan) * small$max_lead[[1L]] * 7L)
stopifnot(nrow(forecast_raw) == nrow(forecast_quantiles))
stopifnot(nrow(forecast_adjustment) == nrow(forecast_quantiles))
stopifnot(all(is.finite(forecast_quantiles$qhat)))
stopifnot(all(is.finite(forecast_quantiles$check_loss)))
stopifnot(all(forecast_crossing$n_crossing_pairs == 0L))
stopifnot(all(forecast_quantiles$full_time_index > forecast_quantiles$fit_window_end_full_time_index))
