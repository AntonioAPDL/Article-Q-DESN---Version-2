registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4j_ids <- c("normal_bridge", "laplace_bridge")
phase4j_base_registry <- registry[registry$scenario_id %in% phase4j_ids, , drop = FALSE]
phase4j_base_registry <- phase4j_base_registry[match(phase4j_ids, phase4j_base_registry$scenario_id), , drop = FALSE]
phase4j_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4j_base_registry$simulated_length <- 34L
phase4j_base_registry$washout_length <- 6L
phase4j_base_registry$train_length <- 18L
phase4j_base_registry$test_length <- 10L
phase4j_base_registry$seed <- c(202607101L, 202607102L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4j_base_registry)

phase4j_launch_registry <- app_joint_qvp_phase4j_build_launch_registry(
  registry = phase4j_base_registry,
  scenario_ids = phase4j_ids,
  n_replicates = 1L,
  seed_base = 202607910L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L
)
stopifnot(nrow(phase4j_launch_registry) == 2L)
stopifnot(!anyDuplicated(phase4j_launch_registry$scenario_id))
stopifnot(all(phase4j_launch_registry$validation_tier == "tau0_candidate_launch"))
stopifnot(all(phase4j_launch_registry$seed_role == "tau0_candidate_launch_replicate_seed"))
stopifnot(all(grepl("__tau0_candidate_launch_r", phase4j_launch_registry$scenario_id, fixed = TRUE)))
stopifnot(!app_joint_qvp_phase4j_contains_nonlaunch_label(
  phase4j_launch_registry$registry_version,
  phase4j_launch_registry$scenario_id,
  phase4j_launch_registry$validation_tier,
  phase4j_launch_registry$seed_role
))

phase4j_grid <- app_joint_qvp_phase4j_tau0_arm_grid(c(0.10, 0.15))
stopifnot(identical(phase4j_grid$arm_id, c("tau0_0p10_primary", "tau0_0p15_comparator")))
stopifnot(identical(phase4j_grid$arm_role, c("primary", "comparator")))
stopifnot(all(phase4j_grid$screen_class == "tau0_candidate_launch"))

phase4j_out <- tempfile("joint_qvp_phase4j_launch_")
phase4j_result <- app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = phase4j_out,
  registry = phase4j_base_registry,
  scenario_ids = phase4j_ids,
  tier = "tau0_candidate_launch",
  tau0_arms = c(0.10, 0.15),
  n_replicates = 1L,
  seed_base = 202607910L,
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

expected_phase4j_labels <- c(
  "launch_arm_grid",
  "launch_registry",
  "launch_run_config",
  "launch_arm_run_manifest",
  "launch_metric_summary",
  "launch_ranking",
  "launch_crossing_by_arm",
  "launch_crossing_by_scenario",
  "launch_crossing_by_family",
  "launch_crossing_by_tau_pair",
  "launch_truth_by_tau",
  "launch_tail_tradeoff_summary",
  "launch_vb_runtime_summary",
  "launch_recommendation",
  "phase4j_readiness_assessment",
  "provenance",
  "readme"
)
phase4j_manifest <- utils::read.csv(file.path(phase4j_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4j_manifest$label, expected_phase4j_labels))
stopifnot(all(nchar(phase4j_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4j_manifest))) {
  artifact_path <- file.path(phase4j_result$out_dir, phase4j_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4j_manifest$sha256[[ii]]))
}

launch_registry <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_registry.csv"), stringsAsFactors = FALSE)
arm_grid <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_arm_grid.csv"), stringsAsFactors = FALSE)
run_config <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_run_config.csv"), stringsAsFactors = FALSE)
metric_summary <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_metric_summary.csv"), stringsAsFactors = FALSE)
launch_ranking <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_ranking.csv"), stringsAsFactors = FALSE)
launch_recommendation <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_recommendation.csv"), stringsAsFactors = FALSE)
assessment <- utils::read.csv(file.path(phase4j_result$out_dir, "phase4j_readiness_assessment.csv"), stringsAsFactors = FALSE)
arm_run_manifest <- utils::read.csv(file.path(phase4j_result$out_dir, "launch_arm_run_manifest.csv"), stringsAsFactors = FALSE)
readme_text <- paste(readLines(file.path(phase4j_result$out_dir, "README.md"), warn = FALSE), collapse = "\n")

stopifnot(identical(launch_registry$scenario_id, phase4j_launch_registry$scenario_id))
stopifnot(identical(as.integer(launch_registry$seed), as.integer(phase4j_launch_registry$seed)))
stopifnot(identical(arm_grid$arm_id, c("tau0_0p10_primary", "tau0_0p15_comparator")))
stopifnot(run_config$phase[[1L]] == "phase4j_tau0_candidate_launch")
stopifnot(run_config$tier[[1L]] == "tau0_candidate_launch")
stopifnot(run_config$primary_arm_id[[1L]] == "tau0_0p10_primary")
stopifnot(run_config$n_launch_registry_rows[[1L]] == nrow(phase4j_launch_registry))
stopifnot(run_config$n_candidate_arms[[1L]] == 2L)
stopifnot(run_config$vb_max_iter[[1L]] == 5L)
stopifnot(app_as_bool(run_config$all_fixture_hashes_verified[[1L]]))
stopifnot(app_as_bool(run_config$all_phase3_manifest_hashes_verified[[1L]]))
stopifnot(!app_joint_qvp_phase4j_contains_nonlaunch_label(
  launch_registry$registry_version,
  launch_registry$scenario_id,
  launch_registry$validation_tier,
  launch_registry$seed_role,
  run_config$phase,
  run_config$tier,
  launch_recommendation$scope
))
stopifnot(!grepl("smoke|pilot|calibration_pilot", readme_text, ignore.case = TRUE))

stopifnot(nrow(metric_summary) == 2L)
stopifnot(all(is.finite(metric_summary$raw_crossing_pairs)))
stopifnot(all(is.finite(metric_summary$contract_crossing_pairs)))
stopifnot(all(metric_summary$contract_crossing_pairs == 0L))
stopifnot(all(is.finite(metric_summary$truth_mae_mean)))
stopifnot(all(c("arm_id", "arm_role", "screen_status", "ranking_score", "rank", "note") %in% names(launch_ranking)))
stopifnot(launch_recommendation$recommendation_status[[1L]] %in% c(
  "blocked_contract_crossing",
  "review_no_tau0_freeze",
  "primary_selected_for_article_candidate_freeze",
  "comparator_selected_for_article_candidate_freeze"
))
stopifnot(assessment$label_status[[1L]] == "pass")
stopifnot(assessment$no_nonlaunch_labels[[1L]])
stopifnot(assessment$total_contract_crossing_pairs[[1L]] == 0L)
stopifnot(all(app_as_bool_vec(arm_run_manifest$manifest_hashes_verified)))

resolve_phase4j_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}
for (ii in seq_len(nrow(arm_run_manifest))) {
  phase3_dir <- resolve_phase4j_path(arm_run_manifest$phase3_out_dir[[ii]])
  phase3_config <- utils::read.csv(file.path(phase3_dir, "run_config.csv"), stringsAsFactors = FALSE)
  arm_id <- arm_run_manifest$arm_id[[ii]]
  grid_row <- arm_grid[arm_grid$arm_id == arm_id, , drop = FALSE]
  stopifnot(all(phase3_config$tau0 == grid_row$tau0[[1L]]))
  stopifnot(all(phase3_config$no_future_test_leakage))
}

audit_result <- app_joint_qvp_audit_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = phase4j_result$out_dir,
  audit_dir = file.path(phase4j_result$out_dir, "phase4j_launch_audit")
)
audit_manifest <- utils::read.csv(file.path(audit_result$audit_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(audit_manifest$sha256) == 64L))
stopifnot(audit_result$health$root_manifest_hashes_verified[[1L]])
stopifnot(audit_result$health$nested_phase3_manifest_hashes_verified[[1L]])
stopifnot(audit_result$health$fixture_manifest_hashes_verified[[1L]])
stopifnot(audit_result$health$no_nonlaunch_labels[[1L]])
stopifnot(audit_result$promotion_plan$requires_duplicate_compute[[1L]] == FALSE)
