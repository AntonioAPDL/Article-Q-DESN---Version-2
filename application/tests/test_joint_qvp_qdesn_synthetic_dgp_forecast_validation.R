registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase3_ids <- c("normal_bridge", "laplace_bridge")
phase3_registry <- registry[registry$scenario_id %in% phase3_ids, , drop = FALSE]
phase3_registry <- phase3_registry[match(phase3_ids, phase3_registry$scenario_id), , drop = FALSE]
phase3_registry$tau_grid <- "0.25,0.5,0.75"
phase3_registry$simulated_length <- 34L
phase3_registry$washout_length <- 6L
phase3_registry$train_length <- 18L
phase3_registry$test_length <- 10L
phase3_registry$seed <- c(202607031L, 202607032L)
app_joint_qvp_validate_synthetic_dgp_registry(phase3_registry)

phase1_dir <- tempfile("joint_qvp_phase3_fixture_")
phase1_result <- app_joint_qvp_materialize_synthetic_dgp_registry(
  out_dir = phase1_dir,
  registry = phase3_registry
)
phase1_manifest <- app_joint_qvp_verify_phase1_fixture_dir(phase1_result$out_dir)
stopifnot(all(phase1_manifest$file_exists))
stopifnot(all(phase1_manifest$hash_verified))

phase1_tables <- app_joint_qvp_load_phase1_fixture_tables(phase1_result$out_dir)
normal_forecast <- app_joint_qvp_phase3_forecast_fixture_from_tables(phase1_tables, "normal_bridge")
normal_origins <- app_joint_qvp_phase3_origin_rows(normal_forecast, max_origins_per_scenario = 4L)
stopifnot(identical(normal_forecast$scenario_id, "normal_bridge"))
stopifnot(length(normal_forecast$test_pos) == 10L)
stopifnot(nrow(normal_origins) == 4L)
stopifnot(all(normal_origins$forecast_role == "test"))
stopifnot(all(normal_origins$forecast_horizon == 1L))
stopifnot(normal_origins$forecast_time_index[[1L]] == normal_forecast$test_start)
stopifnot(normal_origins$available_fit_window_end[[1L]] == normal_forecast$train_end)
stopifnot(normal_origins$available_previous_test_n[[1L]] == 0L)
stopifnot(normal_origins$available_previous_test_n[[2L]] == 1L)
stopifnot(all(normal_origins$available_fit_window_end < normal_origins$forecast_time_index))
stopifnot(all(normal_origins$no_future_test_leakage))
stopifnot(all(is.finite(normal_forecast$y)))
stopifnot(all(is.finite(normal_forecast$Z)))
stopifnot(all(is.finite(normal_forecast$true_q)))
stopifnot(all(normal_forecast$sigma > 0))
stopifnot(sum(normal_forecast$crossing_diagnostics$n_crossing_pairs) == 0L)

phase3_dir <- tempfile("joint_qvp_phase3_forecast_")
phase3_result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
  out_dir = phase3_dir,
  fixture_dir = phase1_result$out_dir,
  scenario_ids = phase3_ids,
  vb_max_iter = 8L,
  adaptive_vb_max_iter_grid = 8L,
  refit_stride = 2L,
  max_origins_per_scenario = 3L
)

expected_phase3_labels <- c(
  "run_config",
  "fixture_source_manifest",
  "forecast_origin_config",
  "forecast_quantiles_raw",
  "forecast_quantiles",
  "forecast_monotone_adjustment",
  "forecast_truth_comparison",
  "pinball_summary",
  "hit_rate_summary",
  "interval_coverage_summary",
  "interval_score_summary",
  "wis_summary",
  "crps_grid_summary",
  "raw_crossing_summary",
  "crossing_summary",
  "vb_convergence_audit",
  "objective_diagnostics",
  "runtime_summary",
  "forecast_validation_assessment",
  "provenance",
  "readme"
)
phase3_manifest <- utils::read.csv(file.path(phase3_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase3_manifest$label, expected_phase3_labels))
stopifnot(all(nchar(phase3_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase3_manifest))) {
  artifact_path <- file.path(phase3_result$out_dir, phase3_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase3_manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(phase3_result$out_dir, "run_config.csv"), stringsAsFactors = FALSE)
forecast_origin_config <- utils::read.csv(file.path(phase3_result$out_dir, "forecast_origin_config.csv"), stringsAsFactors = FALSE)
forecast_quantiles_raw <- utils::read.csv(file.path(phase3_result$out_dir, "forecast_quantiles_raw.csv"), stringsAsFactors = FALSE)
forecast_quantiles <- utils::read.csv(file.path(phase3_result$out_dir, "forecast_quantiles.csv"), stringsAsFactors = FALSE)
forecast_monotone_adjustment <- utils::read.csv(file.path(phase3_result$out_dir, "forecast_monotone_adjustment.csv"), stringsAsFactors = FALSE)
forecast_truth_comparison <- utils::read.csv(file.path(phase3_result$out_dir, "forecast_truth_comparison.csv"), stringsAsFactors = FALSE)
pinball_summary <- utils::read.csv(file.path(phase3_result$out_dir, "pinball_summary.csv"), stringsAsFactors = FALSE)
hit_rate_summary <- utils::read.csv(file.path(phase3_result$out_dir, "hit_rate_summary.csv"), stringsAsFactors = FALSE)
interval_coverage_summary <- utils::read.csv(file.path(phase3_result$out_dir, "interval_coverage_summary.csv"), stringsAsFactors = FALSE)
interval_score_summary <- utils::read.csv(file.path(phase3_result$out_dir, "interval_score_summary.csv"), stringsAsFactors = FALSE)
wis_summary <- utils::read.csv(file.path(phase3_result$out_dir, "wis_summary.csv"), stringsAsFactors = FALSE)
crps_grid_summary <- utils::read.csv(file.path(phase3_result$out_dir, "crps_grid_summary.csv"), stringsAsFactors = FALSE)
raw_crossing_summary <- utils::read.csv(file.path(phase3_result$out_dir, "raw_crossing_summary.csv"), stringsAsFactors = FALSE)
crossing_summary <- utils::read.csv(file.path(phase3_result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
vb_convergence_audit <- utils::read.csv(file.path(phase3_result$out_dir, "vb_convergence_audit.csv"), stringsAsFactors = FALSE)
objective_diagnostics <- utils::read.csv(file.path(phase3_result$out_dir, "objective_diagnostics.csv"), stringsAsFactors = FALSE)
runtime_summary <- utils::read.csv(file.path(phase3_result$out_dir, "runtime_summary.csv"), stringsAsFactors = FALSE)
assessment <- utils::read.csv(file.path(phase3_result$out_dir, "forecast_validation_assessment.csv"), stringsAsFactors = FALSE)

stopifnot(all(c(
  "scenario_id", "n_forecast_origins", "refit_stride", "no_future_test_leakage",
  "tau0", "zeta2", "alpha_prior_sd", "alpha_min_spacing", "rhs_vb_inner", "vb_tol"
) %in% names(run_config)))
stopifnot(all(c("scenario_id", "origin_index", "forecast_time_index", "used_fit_window_end", "refit", "vb_status") %in% names(forecast_origin_config)))
stopifnot(all(c("scenario_id", "method", "origin_index", "tau", "qhat", "true_quantile", "pinball_loss") %in% names(forecast_quantiles_raw)))
stopifnot(all(c("scenario_id", "method", "origin_index", "tau", "qhat", "true_quantile", "pinball_loss") %in% names(forecast_quantiles)))
stopifnot(all(c("scenario_id", "origin_index", "n_adjusted_quantiles", "max_abs_adjustment", "n_raw_crossing_pairs") %in% names(forecast_monotone_adjustment)))
stopifnot(all(c("scenario_id", "method", "tau", "rmse_to_truth", "mae_to_truth") %in% names(forecast_truth_comparison)))
stopifnot(all(c("scenario_id", "method", "tau", "pinball_mean", "truth_pinball_mean") %in% names(pinball_summary)))
stopifnot(all(c("scenario_id", "method", "tau", "empirical_hit_rate", "hit_rate_minus_tau") %in% names(hit_rate_summary)))
stopifnot(all(c("scenario_id", "method", "lower_tau", "upper_tau", "empirical_coverage") %in% names(interval_coverage_summary)))
stopifnot(all(c("scenario_id", "method", "lower_tau", "upper_tau", "interval_score_mean", "interval_width_mean") %in% names(interval_score_summary)))
stopifnot(all(c("scenario_id", "method", "wis_mean", "n_intervals") %in% names(wis_summary)))
stopifnot(all(c("scenario_id", "method", "crps_grid_mean", "n_quantiles") %in% names(crps_grid_summary)))
stopifnot(all(c("scenario_id", "method", "origin_index", "n_crossing_pairs") %in% names(raw_crossing_summary)))
stopifnot(all(c("scenario_id", "method", "origin_index", "n_crossing_pairs") %in% names(crossing_summary)))
stopifnot(all(c("scenario_id", "origin_index", "refit", "status", "converged") %in% names(vb_convergence_audit)))
stopifnot(all(c("scenario_id", "method", "origin_index", "objective_status") %in% names(objective_diagnostics)))
stopifnot(all(c("scenario_id", "origin_index", "component", "elapsed_sec") %in% names(runtime_summary)))
stopifnot(all(c("scenario_id", "implementation_status", "gate_status", "truth_normalized_qhat_distance") %in% names(assessment)))

stopifnot(identical(sort(unique(run_config$scenario_id)), sort(phase3_ids)))
stopifnot(all(run_config$n_forecast_origins == 3L))
stopifnot(all(run_config$no_future_test_leakage))
stopifnot(all(run_config$tau0 == 1))
stopifnot(all(is.infinite(run_config$zeta2)))
stopifnot(all(run_config$alpha_prior_sd == 1))
stopifnot(all(run_config$alpha_min_spacing == 0))
stopifnot(all(run_config$rhs_vb_inner == 5L))
stopifnot(all(run_config$vb_tol == 1.0e-4))
stopifnot(nrow(forecast_origin_config) == length(phase3_ids) * 3L)
stopifnot(all(forecast_origin_config$forecast_role == "test"))
stopifnot(all(forecast_origin_config$forecast_horizon == 1L))
stopifnot(all(forecast_origin_config$used_fit_window_end < forecast_origin_config$forecast_time_index))
stopifnot(all(forecast_origin_config$used_fit_max_time_before_forecast))
stopifnot(nrow(forecast_quantiles_raw) == length(phase3_ids) * 3L * 3L)
stopifnot(nrow(forecast_quantiles) == length(phase3_ids) * 3L * 3L)
stopifnot(all(is.finite(forecast_quantiles_raw$qhat)))
stopifnot(all(is.finite(forecast_quantiles$qhat)))
stopifnot(all(is.finite(forecast_quantiles$true_quantile)))
stopifnot(all(is.finite(forecast_quantiles$pinball_loss)))
stopifnot(nrow(forecast_monotone_adjustment) == length(phase3_ids) * 3L)
stopifnot(all(is.finite(forecast_monotone_adjustment$max_abs_adjustment)))
stopifnot(all(is.finite(forecast_truth_comparison$rmse_to_truth)))
stopifnot(all(is.finite(pinball_summary$pinball_mean)))
stopifnot(all(is.finite(hit_rate_summary$hit_rate_minus_tau)))
stopifnot(nrow(interval_coverage_summary) == length(phase3_ids))
stopifnot(all(interval_coverage_summary$lower_tau == 0.25))
stopifnot(all(interval_coverage_summary$upper_tau == 0.75))
stopifnot(all(is.finite(interval_score_summary$interval_score_mean)))
stopifnot(all(is.finite(wis_summary$wis_mean)))
stopifnot(all(wis_summary$n_intervals == 1L))
stopifnot(all(is.finite(crps_grid_summary$crps_grid_mean)))
stopifnot(all(is.finite(raw_crossing_summary$n_crossing_pairs)))
stopifnot(all(is.finite(crossing_summary$n_crossing_pairs)))
stopifnot(all(crossing_summary$n_crossing_pairs >= 0L))
stopifnot(all(crossing_summary$n_crossing_pairs == 0L))
stopifnot(any(!vb_convergence_audit$refit))
stopifnot(all(is.finite(runtime_summary$elapsed_sec)))
stopifnot(all(assessment$gate_status %in% c("pass", "review", "fail")))
crossed_ids <- crossing_summary$scenario_id[crossing_summary$n_crossing_pairs > 0L]
if (length(crossed_ids)) {
  stopifnot(all(assessment$gate_status[assessment$scenario_id %in% crossed_ids] == "fail"))
}

phase3_repeat_dir <- tempfile("joint_qvp_phase3_forecast_repeat_")
phase3_repeat <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
  out_dir = phase3_repeat_dir,
  fixture_dir = phase1_result$out_dir,
  scenario_ids = phase3_ids,
  vb_max_iter = 8L,
  adaptive_vb_max_iter_grid = 8L,
  refit_stride = 2L,
  max_origins_per_scenario = 3L
)
phase3_repeat_manifest <- utils::read.csv(file.path(phase3_repeat$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stable_labels <- setdiff(expected_phase3_labels, "runtime_summary")
phase3_stable <- phase3_manifest[phase3_manifest$label %in% stable_labels, c("label", "sha256"), drop = FALSE]
phase3_repeat_stable <- phase3_repeat_manifest[phase3_repeat_manifest$label %in% stable_labels, c("label", "sha256"), drop = FALSE]
stopifnot(identical(phase3_stable$label, phase3_repeat_stable$label))
stopifnot(identical(phase3_stable$sha256, phase3_repeat_stable$sha256))
