phase4k_registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4k_ids <- c("normal_bridge", "laplace_bridge")
phase4k_base_registry <- phase4k_registry[phase4k_registry$scenario_id %in% phase4k_ids, , drop = FALSE]
phase4k_base_registry <- phase4k_base_registry[match(phase4k_ids, phase4k_base_registry$scenario_id), , drop = FALSE]
phase4k_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4k_base_registry$simulated_length <- 34L
phase4k_base_registry$washout_length <- 6L
phase4k_base_registry$train_length <- 18L
phase4k_base_registry$test_length <- 10L
phase4k_base_registry$seed <- c(202607111L, 202607112L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4k_base_registry)

phase4k_launch_dir <- tempfile("joint_qvp_phase4k_launch_")
phase4k_launch <- app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = phase4k_launch_dir,
  registry = phase4k_base_registry,
  scenario_ids = phase4k_ids,
  tier = "tau0_candidate_launch",
  tau0_arms = c(0.10, 0.15),
  n_replicates = 1L,
  seed_base = 202607920L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L,
  vb_max_iter = 5L,
  adaptive_vb_max_iter_grid = 5L,
  refit_stride = 99L,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = 2L
)
writeLines("0", file.path(phase4k_launch$out_dir, "phase4j_launch.exitcode"), useBytes = TRUE)

phase4k_audit <- app_joint_qvp_audit_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = phase4k_launch$out_dir,
  audit_dir = file.path(phase4k_launch$out_dir, "phase4j_launch_audit")
)
stopifnot(phase4k_audit$health$root_manifest_hashes_verified[[1L]])
stopifnot(phase4k_audit$health$nested_phase3_manifest_hashes_verified[[1L]])
stopifnot(phase4k_audit$health$fixture_manifest_hashes_verified[[1L]])

phase4k_freeze_dir <- tempfile("joint_qvp_phase4k_freeze_")
phase4k_freeze <- app_joint_qvp_freeze_synthetic_dgp_phase4k_article_candidate(
  launch_dir = phase4k_launch$out_dir,
  audit_dir = phase4k_audit$audit_dir,
  freeze_dir = phase4k_freeze_dir,
  expected_selected_arm = "",
  allow_selected_arm_override = TRUE
)

phase4k_expected_freeze_files <- c(
  "freeze_decision_summary.csv",
  "freeze_source_manifest_verification.csv",
  "freeze_launch_run_config.csv",
  "freeze_tau0_arm_comparison.csv",
  "freeze_selected_arm_metric_summary.csv",
  "freeze_selected_arm_truth_by_tau.csv",
  "freeze_selected_arm_scenario_truth_summary.csv",
  "freeze_selected_arm_crossing_summary.csv",
  "freeze_selected_arm_hit_coverage_summary.csv",
  "freeze_selected_arm_vb_runtime_summary.csv",
  "freeze_selected_arm_scenario_assessment.csv",
  "freeze_selected_arm_monotone_adjustment_events.csv",
  "freeze_selected_arm_monotone_adjustment_summary.csv",
  "freeze_large_file_registry.csv",
  "selected_phase3_artifact_manifest.csv",
  "provenance.csv",
  "README.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(phase4k_freeze$freeze_dir, phase4k_expected_freeze_files))))

phase4k_manifest <- utils::read.csv(file.path(phase4k_freeze$freeze_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(phase4k_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4k_manifest))) {
  artifact_path <- file.path(phase4k_freeze$freeze_dir, phase4k_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4k_manifest$sha256[[ii]]))
}

phase4k_decision <- utils::read.csv(file.path(phase4k_freeze$freeze_dir, "freeze_decision_summary.csv"), stringsAsFactors = FALSE)
phase4k_source_manifest <- utils::read.csv(file.path(phase4k_freeze$freeze_dir, "freeze_source_manifest_verification.csv"), stringsAsFactors = FALSE)
phase4k_large_registry <- utils::read.csv(file.path(phase4k_freeze$freeze_dir, "freeze_large_file_registry.csv"), stringsAsFactors = FALSE)
phase4k_selected_metric <- utils::read.csv(file.path(phase4k_freeze$freeze_dir, "freeze_selected_arm_metric_summary.csv"), stringsAsFactors = FALSE)

stopifnot(phase4k_decision$freeze_status[[1L]] %in% c("ready", "blocked"))
stopifnot(phase4k_decision$requires_duplicate_compute[[1L]] == FALSE)
stopifnot(phase4k_decision$selected_contract_crossing_pairs[[1L]] == 0L)
stopifnot(all(app_as_bool_vec(phase4k_source_manifest$all_hashes_verified)))
stopifnot(nrow(phase4k_large_registry) > 0L)
stopifnot(all(app_as_bool_vec(phase4k_large_registry$file_exists)))
stopifnot(all(app_as_bool_vec(phase4k_large_registry$hash_verified)))
stopifnot(any(app_as_bool_vec(phase4k_large_registry$is_large_or_primary_forecast_file)))
stopifnot(all(c("truth_mae_mean", "truth_rmse_mean", "pinball_mean") %in% names(phase4k_selected_metric)))
stopifnot(all(is.finite(as.numeric(phase4k_selected_metric[1L, c("truth_mae_mean", "truth_rmse_mean", "pinball_mean")]))))
