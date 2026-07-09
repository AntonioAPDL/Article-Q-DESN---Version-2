registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4_ids <- c("normal_bridge", "laplace_bridge")
phase4_base_registry <- registry[registry$scenario_id %in% phase4_ids, , drop = FALSE]
phase4_base_registry <- phase4_base_registry[match(phase4_ids, phase4_base_registry$scenario_id), , drop = FALSE]
phase4_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4_base_registry$simulated_length <- 34L
phase4_base_registry$washout_length <- 6L
phase4_base_registry$train_length <- 18L
phase4_base_registry$test_length <- 10L
phase4_base_registry$seed <- c(202607041L, 202607042L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4_base_registry)

phase4_registry_a <- app_joint_qvp_phase4_build_calibration_registry(
  registry = phase4_base_registry,
  scenario_ids = phase4_ids,
  tier = "smoke",
  n_replicates = 2L,
  seed_base = 202607410L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L
)
phase4_registry_b <- app_joint_qvp_phase4_build_calibration_registry(
  registry = phase4_base_registry,
  scenario_ids = phase4_ids,
  tier = "smoke",
  n_replicates = 2L,
  seed_base = 202607410L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L
)
stopifnot(identical(phase4_registry_a, phase4_registry_b))
stopifnot(nrow(phase4_registry_a) == length(phase4_ids) * 2L)
stopifnot(length(unique(phase4_registry_a$scenario_id)) == nrow(phase4_registry_a))
stopifnot(all(phase4_registry_a$base_scenario_id %in% phase4_ids))
stopifnot(all(phase4_registry_a$validation_tier == "smoke"))
stopifnot(all(phase4_registry_a$seed_role == "smoke_replicate_seed"))
stopifnot(all(table(phase4_registry_a$replicate_id) == length(phase4_ids)))
stopifnot(length(unique(phase4_registry_a$seed)) == nrow(phase4_registry_a))
stopifnot(all(phase4_registry_a$simulated_length == phase4_registry_a$washout_length + phase4_registry_a$train_length + phase4_registry_a$test_length))
app_joint_qvp_validate_synthetic_dgp_registry(phase4_registry_a)

phase4_dir <- tempfile("joint_qvp_phase4_calibration_")
phase4_result <- app_joint_qvp_run_synthetic_dgp_forecast_calibration(
  out_dir = phase4_dir,
  registry = phase4_base_registry,
  scenario_ids = phase4_ids,
  tier = "smoke",
  n_replicates = 1L,
  seed_base = 202607410L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L,
  vb_max_iter = 6L,
  adaptive_vb_max_iter_grid = 6L,
  refit_stride = 99L,
  max_origins_per_scenario = 2L
)

expected_phase4_labels <- c(
  "calibration_registry",
  "calibration_run_config",
  "phase3_artifact_manifest",
  "forecast_metric_distribution_summary",
  "forecast_metric_by_scenario_summary",
  "forecast_metric_by_family_summary",
  "forecast_metric_by_tau_summary",
  "interval_metric_summary",
  "vb_convergence_calibration_summary",
  "runtime_calibration_summary",
  "forecast_calibrated_thresholds",
  "forecast_calibration_assessment",
  "article_candidate_run_plan",
  "provenance",
  "readme"
)
phase4_manifest <- utils::read.csv(file.path(phase4_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4_manifest$label, expected_phase4_labels))
stopifnot(all(nchar(phase4_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4_manifest))) {
  artifact_path <- file.path(phase4_result$out_dir, phase4_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4_manifest$sha256[[ii]]))
}

calibration_registry <- utils::read.csv(file.path(phase4_result$out_dir, "calibration_registry.csv"), stringsAsFactors = FALSE)
calibration_run_config <- utils::read.csv(file.path(phase4_result$out_dir, "calibration_run_config.csv"), stringsAsFactors = FALSE)
phase3_artifact_manifest <- utils::read.csv(file.path(phase4_result$out_dir, "phase3_artifact_manifest.csv"), stringsAsFactors = FALSE)
forecast_metric_distribution_summary <- utils::read.csv(file.path(phase4_result$out_dir, "forecast_metric_distribution_summary.csv"), stringsAsFactors = FALSE)
forecast_metric_by_scenario_summary <- utils::read.csv(file.path(phase4_result$out_dir, "forecast_metric_by_scenario_summary.csv"), stringsAsFactors = FALSE)
forecast_metric_by_family_summary <- utils::read.csv(file.path(phase4_result$out_dir, "forecast_metric_by_family_summary.csv"), stringsAsFactors = FALSE)
forecast_metric_by_tau_summary <- utils::read.csv(file.path(phase4_result$out_dir, "forecast_metric_by_tau_summary.csv"), stringsAsFactors = FALSE)
interval_metric_summary <- utils::read.csv(file.path(phase4_result$out_dir, "interval_metric_summary.csv"), stringsAsFactors = FALSE)
vb_convergence_calibration_summary <- utils::read.csv(file.path(phase4_result$out_dir, "vb_convergence_calibration_summary.csv"), stringsAsFactors = FALSE)
runtime_calibration_summary <- utils::read.csv(file.path(phase4_result$out_dir, "runtime_calibration_summary.csv"), stringsAsFactors = FALSE)
forecast_calibrated_thresholds <- utils::read.csv(file.path(phase4_result$out_dir, "forecast_calibrated_thresholds.csv"), stringsAsFactors = FALSE)
forecast_calibration_assessment <- utils::read.csv(file.path(phase4_result$out_dir, "forecast_calibration_assessment.csv"), stringsAsFactors = FALSE)
article_candidate_run_plan <- utils::read.csv(file.path(phase4_result$out_dir, "article_candidate_run_plan.csv"), stringsAsFactors = FALSE)

stopifnot(all(c("scenario_id", "base_scenario_id", "replicate_id", "validation_tier", "seed_role") %in% names(calibration_registry)))
stopifnot(all(c("validation_tier", "n_registry_rows", "n_replicates", "phase3_out_dir") %in% names(calibration_run_config)))
stopifnot(all(c("label", "relative_path", "sha256", "file_exists", "hash_verified") %in% names(phase3_artifact_manifest)))
stopifnot(all(c("metric", "n", "finite_n", "q90", "q95") %in% names(forecast_metric_distribution_summary)))
stopifnot(all(c("scenario_id", "base_scenario_id", "gate_status", "runtime_total_sec") %in% names(forecast_metric_by_scenario_summary)))
stopifnot(all(c("distribution_family", "metric", "finite_n") %in% names(forecast_metric_by_family_summary)))
stopifnot(all(c("tau", "metric", "finite_n") %in% names(forecast_metric_by_tau_summary)))
stopifnot(all(c("scenario_id", "lower_tau", "upper_tau", "abs_coverage_error") %in% names(interval_metric_summary)))
stopifnot(all(c("scenario_id", "max_iter_rate", "objective_review_rate") %in% names(vb_convergence_calibration_summary)))
stopifnot(all(c("scenario_id", "runtime_total_sec", "refit_runtime_sec") %in% names(runtime_calibration_summary)))
stopifnot(all(c("threshold_name", "metric", "recommended_pass_threshold", "rationale", "status") %in% names(forecast_calibrated_thresholds)))
stopifnot(all(c("scope", "implementation_status", "gate_status", "threshold_rows") %in% names(forecast_calibration_assessment)))
stopifnot(all(c("base_scenario_id", "validation_tier", "status", "rationale") %in% names(article_candidate_run_plan)))

stopifnot(nrow(calibration_registry) == length(phase4_ids))
stopifnot(identical(sort(calibration_registry$base_scenario_id), sort(phase4_ids)))
stopifnot(calibration_run_config$validation_tier[[1L]] == "smoke")
stopifnot(calibration_run_config$n_registry_rows[[1L]] == length(phase4_ids))
stopifnot(file.exists(file.path(phase4_result$out_dir, "phase3_forecast_validation", "artifact_manifest.csv")))
stopifnot(all(app_as_bool_vec(phase3_artifact_manifest$file_exists)))
stopifnot(all(app_as_bool_vec(phase3_artifact_manifest$hash_verified)))
stopifnot(all(forecast_metric_distribution_summary$finite_n > 0L))
stopifnot(all(is.finite(forecast_metric_distribution_summary$q90)))
stopifnot(all(is.finite(forecast_metric_by_scenario_summary$truth_normalized_qhat_distance)))
stopifnot(all(is.finite(forecast_metric_by_family_summary$q90)))
stopifnot(all(is.finite(forecast_metric_by_tau_summary$tau)))
stopifnot(all(is.finite(forecast_metric_by_tau_summary$q90)))
stopifnot(all(is.finite(interval_metric_summary$abs_coverage_error)))
stopifnot(all(is.finite(vb_convergence_calibration_summary$max_iter_rate)))
stopifnot(all(is.finite(runtime_calibration_summary$runtime_total_sec)))
stopifnot(all(runtime_calibration_summary$runtime_total_sec >= 0))
stopifnot(all(is.finite(forecast_calibrated_thresholds$recommended_pass_threshold)))
stopifnot(all(nzchar(forecast_calibrated_thresholds$rationale)))
stopifnot(all(forecast_calibrated_thresholds$status %in% c("candidate", "needs_more_calibration", "ready_for_article_candidate")))
stopifnot(forecast_calibration_assessment$implementation_status[[1L]] == "pass")
stopifnot(forecast_calibration_assessment$gate_status[[1L]] %in% c("pass", "review", "fail"))
stopifnot(forecast_calibration_assessment$total_crossing_pairs[[1L]] == 0)

phase4_repeat_dir <- tempfile("joint_qvp_phase4_calibration_repeat_")
phase4_repeat <- app_joint_qvp_run_synthetic_dgp_forecast_calibration(
  out_dir = phase4_repeat_dir,
  registry = phase4_base_registry,
  scenario_ids = phase4_ids,
  tier = "smoke",
  n_replicates = 1L,
  seed_base = 202607410L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L,
  vb_max_iter = 6L,
  adaptive_vb_max_iter_grid = 6L,
  refit_stride = 99L,
  max_origins_per_scenario = 2L
)
phase4_repeat_manifest <- utils::read.csv(file.path(phase4_repeat$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
unstable_phase4_labels <- c(
  "calibration_run_config",
  "phase3_artifact_manifest",
  "forecast_metric_by_scenario_summary",
  "runtime_calibration_summary",
  "provenance"
)
stable_phase4_labels <- setdiff(expected_phase4_labels, unstable_phase4_labels)
phase4_stable <- phase4_manifest[phase4_manifest$label %in% stable_phase4_labels, c("label", "sha256"), drop = FALSE]
phase4_repeat_stable <- phase4_repeat_manifest[phase4_repeat_manifest$label %in% stable_phase4_labels, c("label", "sha256"), drop = FALSE]
stopifnot(identical(phase4_stable$label, phase4_repeat_stable$label))
stopifnot(identical(phase4_stable$sha256, phase4_repeat_stable$sha256))
