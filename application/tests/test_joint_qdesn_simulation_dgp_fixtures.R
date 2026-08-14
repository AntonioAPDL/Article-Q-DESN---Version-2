repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN fixture test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))

registry <- app_joint_qdesn_load_simulation_registry()
stopifnot(nrow(registry) == 9L)
stopifnot(all(registry$simulated_length == 12000L))
stopifnot(all(registry$dgp_warmup_length == 2000L))
stopifnot(all(registry$effective_length == 10000L))
stopifnot(all(registry$analysis_window_length == 2000L))
stopifnot(all(registry$desn_washout_length == 500L))
stopifnot(all(registry$train_length == 500L))
stopifnot(all(registry$test_length == 1000L))
stopifnot(all(registry$washout_length == 10500L))
stopifnot(all(registry$forecast_origin_stride == 30L))
stopifnot(all(registry$max_lead == 30L))
app_joint_qdesn_validate_simulation_registry(registry)

small <- registry[registry$scenario_id %in% c("normal_bridge", "gaussian_mixture_bridge"), , drop = FALSE]
small <- small[match(c("normal_bridge", "gaussian_mixture_bridge"), small$scenario_id), , drop = FALSE]
small$simulated_length <- 60L
small$dgp_warmup_length <- 10L
small$effective_length <- 50L
small$analysis_window_length <- 20L
small$desn_washout_length <- 5L
small$train_length <- 5L
small$fit_length <- 5L
small$test_length <- 10L
small$validation_length <- 10L
small$washout_length <- small$dgp_warmup_length + (small$effective_length - small$analysis_window_length) + small$desn_washout_length
small$forecast_origin_stride <- 5L
small$max_lead <- 5L
small$seed <- c(202607211L, 202607212L)
app_joint_qdesn_validate_simulation_registry(small)

out_dir <- tempfile("joint_qdesn_sim_fixtures_")
result <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = out_dir,
  registry = small,
  registry_path = app_joint_qdesn_default_simulation_registry_path()
)

expected_labels <- c(
  "run_config",
  "frozen_registry",
  "scenario_summary",
  "observed_series",
  "design_matrix",
  "true_quantile_wide",
  "true_quantile_long",
  "split_metadata",
  "dgp_parameters",
  "forecast_origin_plan",
  "oracle_policy",
  "crossing_summary",
  "fixture_validation",
  "provenance",
  "readme"
)
manifest <- utils::read.csv(file.path(result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(manifest$label, expected_labels))
stopifnot(all(nchar(manifest$sha256) == 64L))
for (ii in seq_len(nrow(manifest))) {
  artifact_path <- file.path(result$out_dir, manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(result$out_dir, "run_config.csv"), stringsAsFactors = FALSE)
scenario_summary <- utils::read.csv(file.path(result$out_dir, "scenario_summary.csv"), stringsAsFactors = FALSE)
observed <- utils::read.csv(file.path(result$out_dir, "observed_series.csv"), stringsAsFactors = FALSE)
design <- utils::read.csv(file.path(result$out_dir, "design_matrix.csv"), stringsAsFactors = FALSE)
true_wide <- utils::read.csv(file.path(result$out_dir, "true_quantile_wide.csv"), stringsAsFactors = FALSE)
true_long <- utils::read.csv(file.path(result$out_dir, "true_quantile_long.csv"), stringsAsFactors = FALSE)
split_metadata <- utils::read.csv(file.path(result$out_dir, "split_metadata.csv"), stringsAsFactors = FALSE)
forecast_origin_plan <- utils::read.csv(file.path(result$out_dir, "forecast_origin_plan.csv"), stringsAsFactors = FALSE)
oracle_policy <- utils::read.csv(file.path(result$out_dir, "oracle_policy.csv"), stringsAsFactors = FALSE)
validation <- utils::read.csv(file.path(result$out_dir, "fixture_validation.csv"), stringsAsFactors = FALSE)

stopifnot(run_config$fixture_layer_only[[1L]])
stopifnot(!run_config$model_fit_launched[[1L]])
stopifnot(!run_config$mcmc_launched[[1L]])
stopifnot(run_config$n_scenarios[[1L]] == 2L)
stopifnot(run_config$total_observed_rows[[1L]] == 120L)

stopifnot(nrow(scenario_summary) == 2L)
stopifnot(all(scenario_summary$simulated_length == 60L))
stopifnot(all(scenario_summary$analysis_window_length == 20L))
stopifnot(all(scenario_summary$desn_washout_length == 5L))
stopifnot(all(scenario_summary$fit_length == 5L))
stopifnot(all(scenario_summary$validation_length == 10L))
stopifnot(all(scenario_summary$total_true_crossing_pairs == 0L))

stopifnot(nrow(observed) == 120L)
stopifnot(nrow(design) == 120L)
stopifnot(nrow(true_wide) == 120L)
stopifnot(nrow(true_long) == 120L * 7L)
stopifnot(all(is.finite(observed$y)))
stopifnot(all(is.finite(observed$sigma)))
stopifnot(all(observed$sigma > 0))
feature_cols <- setdiff(names(design), c("scenario_id", "full_time_index", "effective_index", "analysis_window_index", "role", "role_index", "retained_after_desn_index"))
stopifnot(all(is.finite(as.matrix(design[, feature_cols, drop = FALSE]))))
q_cols <- grep("^q_tau_", names(true_wide), value = TRUE)
stopifnot(length(q_cols) == 7L)
stopifnot(all(is.finite(as.matrix(true_wide[, q_cols, drop = FALSE]))))
for (ii in seq_len(nrow(true_wide))) {
  stopifnot(all(diff(as.numeric(true_wide[ii, q_cols])) >= -1.0e-10))
}

for (sid in unique(observed$scenario_id)) {
  roles <- table(observed$role[observed$scenario_id == sid])
  stopifnot(roles[["dgp_warmup"]] == 10L)
  stopifnot(roles[["effective_pre_analysis"]] == 30L)
  stopifnot(roles[["desn_washout"]] == 5L)
  stopifnot(roles[["fit"]] == 5L)
  stopifnot(roles[["validation"]] == 10L)
}

stopifnot(all(split_metadata$analysis_effective_start == 31L))
stopifnot(all(split_metadata$analysis_effective_end == 50L))
stopifnot(all(split_metadata$desn_washout_effective_start == 31L))
stopifnot(all(split_metadata$desn_washout_effective_end == 35L))
stopifnot(all(split_metadata$fit_effective_start == 36L))
stopifnot(all(split_metadata$fit_effective_end == 40L))
stopifnot(all(split_metadata$validation_effective_start == 41L))
stopifnot(all(split_metadata$validation_effective_end == 50L))

stopifnot(nrow(forecast_origin_plan) == 4L)
stopifnot(all(forecast_origin_plan$n_leads == 5L))
stopifnot(all(forecast_origin_plan$origin_stride == 5L))
stopifnot(all(!forecast_origin_plan$refit_within_block))
stopifnot(all(forecast_origin_plan$no_future_validation_leakage))
stopifnot(all(forecast_origin_plan$target_end_effective_index <= 50L))
stopifnot(all(forecast_origin_plan$fit_window_start_effective_index == 36L))
stopifnot(all(forecast_origin_plan$fit_window_end_effective_index == 40L))

stopifnot(all(oracle_policy$status == "pass"))
stopifnot(identical(oracle_policy$truth_quantile_method, c("analytic", "numerical")))
stopifnot(all(!oracle_policy$recompute_inside_fit_or_forecast))
stopifnot(all(validation$status == "pass"))
