registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4b_ids <- c("normal_bridge")
phase4b_base_registry <- registry[registry$scenario_id %in% phase4b_ids, , drop = FALSE]
phase4b_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4b_base_registry$simulated_length <- 34L
phase4b_base_registry$washout_length <- 6L
phase4b_base_registry$train_length <- 18L
phase4b_base_registry$test_length <- 10L
phase4b_base_registry$seed <- 202607051L
app_joint_qvp_validate_synthetic_dgp_registry(phase4b_base_registry)

phase4b_phase4_dir <- tempfile("joint_qvp_phase4b_source_")
phase4b_phase4 <- app_joint_qvp_run_synthetic_dgp_forecast_calibration(
  out_dir = phase4b_phase4_dir,
  registry = phase4b_base_registry,
  scenario_ids = phase4b_ids,
  tier = "smoke",
  n_replicates = 1L,
  seed_base = 202607510L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L,
  vb_max_iter = 6L,
  adaptive_vb_max_iter_grid = 6L,
  refit_stride = 99L,
  max_origins_per_scenario = 2L
)

phase4b_dir <- tempfile("joint_qvp_phase4b_audit_")
phase4b_audit <- app_joint_qvp_audit_synthetic_dgp_forecast_calibration(
  phase4_dir = phase4b_phase4$out_dir,
  out_dir = phase4b_dir
)

expected_phase4b_labels <- c(
  "calibration_readiness_summary",
  "threshold_readiness_audit",
  "scenario_failure_mode_audit",
  "family_failure_mode_audit",
  "tau_failure_mode_audit",
  "vb_runtime_readiness_audit",
  "article_candidate_recommendation",
  "provenance",
  "readme"
)
phase4b_manifest <- utils::read.csv(file.path(phase4b_audit$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4b_manifest$label, expected_phase4b_labels))
stopifnot(all(nchar(phase4b_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4b_manifest))) {
  artifact_path <- file.path(phase4b_audit$out_dir, phase4b_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4b_manifest$sha256[[ii]]))
}

calibration_readiness_summary <- utils::read.csv(file.path(phase4b_audit$out_dir, "calibration_readiness_summary.csv"), stringsAsFactors = FALSE)
threshold_readiness_audit <- utils::read.csv(file.path(phase4b_audit$out_dir, "threshold_readiness_audit.csv"), stringsAsFactors = FALSE)
scenario_failure_mode_audit <- utils::read.csv(file.path(phase4b_audit$out_dir, "scenario_failure_mode_audit.csv"), stringsAsFactors = FALSE)
family_failure_mode_audit <- utils::read.csv(file.path(phase4b_audit$out_dir, "family_failure_mode_audit.csv"), stringsAsFactors = FALSE)
tau_failure_mode_audit <- utils::read.csv(file.path(phase4b_audit$out_dir, "tau_failure_mode_audit.csv"), stringsAsFactors = FALSE)
vb_runtime_readiness_audit <- utils::read.csv(file.path(phase4b_audit$out_dir, "vb_runtime_readiness_audit.csv"), stringsAsFactors = FALSE)
article_candidate_recommendation <- utils::read.csv(file.path(phase4b_audit$out_dir, "article_candidate_recommendation.csv"), stringsAsFactors = FALSE)

stopifnot(all(c("scope", "phase4_manifest_hashes_verified", "phase3_manifest_hashes_verified", "gate_status", "recommendation_status") %in% names(calibration_readiness_summary)))
stopifnot(all(c("threshold_name", "finite_pass_threshold", "support_status", "audit_status", "note") %in% names(threshold_readiness_audit)))
stopifnot(all(c("scenario_id", "hard_gate_status", "model_behavior_review", "compute_control_review", "readiness_status", "review_reason") %in% names(scenario_failure_mode_audit)))
stopifnot(all(c("distribution_family", "hard_pass_count", "review_count", "readiness_status") %in% names(family_failure_mode_audit)))
stopifnot(all(c("tau", "metric", "instability_ratio_q95_to_median", "audit_status") %in% names(tau_failure_mode_audit)))
stopifnot(all(c("scenario_id", "max_iter_rate", "runtime_total_sec", "readiness_status") %in% names(vb_runtime_readiness_audit)))
stopifnot(all(c("recommendation_status", "article_candidate_ready", "recommended_next_command") %in% names(article_candidate_recommendation)))

stopifnot(nrow(calibration_readiness_summary) == 1L)
stopifnot(isTRUE(app_as_bool_vec(calibration_readiness_summary$phase4_manifest_hashes_verified)[[1L]]))
stopifnot(isTRUE(app_as_bool_vec(calibration_readiness_summary$phase3_manifest_hashes_verified)[[1L]]))
stopifnot(isTRUE(app_as_bool_vec(calibration_readiness_summary$no_future_test_leakage)[[1L]]))
stopifnot(isTRUE(app_as_bool_vec(calibration_readiness_summary$finite_forecasts_and_scores)[[1L]]))
stopifnot(calibration_readiness_summary$total_crossing_pairs[[1L]] == 0)
stopifnot(calibration_readiness_summary$gate_status[[1L]] %in% c("pass", "review", "fail"))
stopifnot(article_candidate_recommendation$recommendation_status[[1L]] %in% c("ready_for_article_candidate", "review_before_article_candidate", "blocked_fix_implementation"))
stopifnot(nzchar(article_candidate_recommendation$article_candidate_command[[1L]]))
if (!is.na(article_candidate_recommendation$recommended_next_command[[1L]])) {
  stopifnot(nzchar(article_candidate_recommendation$recommended_next_command[[1L]]))
}
stopifnot(all(threshold_readiness_audit$audit_status %in% c("pass", "review", "fail")))
stopifnot(all(scenario_failure_mode_audit$hard_gate_status %in% c("pass", "fail")))
stopifnot(all(is.finite(tau_failure_mode_audit$q90)))
stopifnot(all(is.finite(vb_runtime_readiness_audit$runtime_total_sec)))
