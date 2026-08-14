registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4i_ids <- c("normal_bridge", "laplace_bridge")
phase4i_base_registry <- registry[registry$scenario_id %in% phase4i_ids, , drop = FALSE]
phase4i_base_registry <- phase4i_base_registry[match(phase4i_ids, phase4i_base_registry$scenario_id), , drop = FALSE]
phase4i_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4i_base_registry$simulated_length <- 34L
phase4i_base_registry$washout_length <- 6L
phase4i_base_registry$train_length <- 18L
phase4i_base_registry$test_length <- 10L
phase4i_base_registry$seed <- c(202607091L, 202607092L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4i_base_registry)

phase4i_candidate_registry <- app_joint_qvp_phase4i_build_candidate_registry(
  registry = phase4i_base_registry,
  scenario_ids = phase4i_ids,
  tier = "smoke",
  n_replicates = 1L,
  seed_base = 202607900L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L
)
stopifnot(nrow(phase4i_candidate_registry) == 2L)
stopifnot(!anyDuplicated(phase4i_candidate_registry$scenario_id))
stopifnot(all(phase4i_candidate_registry$validation_tier == "smoke"))
stopifnot(length(unique(phase4i_candidate_registry$seed)) == nrow(phase4i_candidate_registry))

phase4i_grid <- app_joint_qvp_phase4i_tau0_arm_grid(c(0.10, 0.15))
stopifnot(identical(phase4i_grid$arm_id, c("tau0_0p10_primary", "tau0_0p15_comparator")))
stopifnot(identical(phase4i_grid$arm_role, c("primary", "comparator")))
stopifnot(all(phase4i_grid$zeta2 == Inf))
stopifnot(all(phase4i_grid$alpha_prior_sd == 1))

phase4i_out <- tempfile("joint_qvp_phase4i_tau0_")
phase4i_result <- app_joint_qvp_run_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot(
  out_dir = phase4i_out,
  registry = phase4i_base_registry,
  scenario_ids = phase4i_ids,
  tier = "smoke",
  tau0_arms = c(0.10, 0.15),
  n_replicates = 1L,
  seed_base = 202607900L,
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

expected_phase4i_labels <- c(
  "candidate_arm_grid",
  "candidate_calibration_registry",
  "candidate_run_config",
  "candidate_arm_run_manifest",
  "candidate_metric_summary",
  "candidate_ranking",
  "candidate_crossing_by_arm",
  "candidate_crossing_by_scenario",
  "candidate_crossing_by_family",
  "candidate_crossing_by_tau_pair",
  "candidate_truth_by_tau",
  "candidate_tail_tradeoff_summary",
  "candidate_vb_runtime_summary",
  "candidate_recommendation",
  "phase4i_readiness_assessment",
  "provenance",
  "readme"
)
phase4i_manifest <- utils::read.csv(file.path(phase4i_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4i_manifest$label, expected_phase4i_labels))
stopifnot(all(nchar(phase4i_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4i_manifest))) {
  artifact_path <- file.path(phase4i_result$out_dir, phase4i_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4i_manifest$sha256[[ii]]))
}

candidate_registry <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_calibration_registry.csv"), stringsAsFactors = FALSE)
arm_grid <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_arm_grid.csv"), stringsAsFactors = FALSE)
run_config <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_run_config.csv"), stringsAsFactors = FALSE)
metric_summary <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_metric_summary.csv"), stringsAsFactors = FALSE)
candidate_ranking <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_ranking.csv"), stringsAsFactors = FALSE)
crossing_by_arm <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_crossing_by_arm.csv"), stringsAsFactors = FALSE)
crossing_by_scenario <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_crossing_by_scenario.csv"), stringsAsFactors = FALSE)
crossing_by_family <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_crossing_by_family.csv"), stringsAsFactors = FALSE)
crossing_by_tau_pair <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_crossing_by_tau_pair.csv"), stringsAsFactors = FALSE)
truth_by_tau <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_truth_by_tau.csv"), stringsAsFactors = FALSE)
tail_tradeoff <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_tail_tradeoff_summary.csv"), stringsAsFactors = FALSE)
vb_runtime <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_vb_runtime_summary.csv"), stringsAsFactors = FALSE)
recommendation <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_recommendation.csv"), stringsAsFactors = FALSE)
assessment <- utils::read.csv(file.path(phase4i_result$out_dir, "phase4i_readiness_assessment.csv"), stringsAsFactors = FALSE)
arm_run_manifest <- utils::read.csv(file.path(phase4i_result$out_dir, "candidate_arm_run_manifest.csv"), stringsAsFactors = FALSE)

stopifnot(identical(candidate_registry$scenario_id, phase4i_candidate_registry$scenario_id))
stopifnot(identical(as.integer(candidate_registry$seed), as.integer(phase4i_candidate_registry$seed)))
stopifnot(identical(arm_grid$arm_id, c("tau0_0p10_primary", "tau0_0p15_comparator")))
stopifnot(run_config$phase[[1L]] == "phase4i_tau0_candidate_calibration_pilot")
stopifnot(run_config$tier[[1L]] == "smoke")
stopifnot(run_config$primary_arm_id[[1L]] == "tau0_0p10_primary")
stopifnot(run_config$n_candidate_registry_rows[[1L]] == nrow(phase4i_candidate_registry))
stopifnot(run_config$n_candidate_arms[[1L]] == 2L)
stopifnot(run_config$vb_max_iter[[1L]] == 5L)
stopifnot(app_as_bool(run_config$all_fixture_hashes_verified[[1L]]))
stopifnot(app_as_bool(run_config$all_phase3_manifest_hashes_verified[[1L]]))

stopifnot(nrow(metric_summary) == 2L)
stopifnot(all(is.finite(metric_summary$raw_crossing_pairs)))
stopifnot(all(is.finite(metric_summary$contract_crossing_pairs)))
stopifnot(all(metric_summary$contract_crossing_pairs == 0L))
stopifnot(all(is.finite(metric_summary$truth_mae_mean)))
stopifnot(all(c("arm_id", "arm_role", "screen_status", "ranking_score", "rank", "note") %in% names(candidate_ranking)))
stopifnot("reference" %in% candidate_ranking$screen_status)
stopifnot(all(c("arm_id", "raw_crossing_pairs", "contract_crossing_pairs") %in% names(crossing_by_arm)))
stopifnot(all(c("scenario_id", "base_scenario_id", "raw_crossing_pairs", "contract_crossing_pairs") %in% names(crossing_by_scenario)))
stopifnot(all(c("distribution_family", "raw_crossing_pairs", "contract_crossing_pairs") %in% names(crossing_by_family)))
stopifnot(all(c("lower_tau", "upper_tau", "raw_crossing_pairs", "mean_true_gap") %in% names(crossing_by_tau_pair)))
stopifnot(all(is.finite(crossing_by_tau_pair$raw_crossing_pairs)))
stopifnot(all(c("tau", "mae_to_truth_mean", "n_forecasts") %in% names(truth_by_tau)))
stopifnot(all(is.finite(truth_by_tau$mae_to_truth_mean)))
stopifnot(all(c("truth_mae_tau095", "upper_tail_090_095_raw_crossing_pairs") %in% names(tail_tradeoff)))
stopifnot(all(is.finite(vb_runtime$runtime_total_sec)))
stopifnot(recommendation$recommendation_status[[1L]] %in% c(
  "blocked_contract_crossing",
  "review_nonfinite_candidate_metric",
  "primary_candidate_for_calibration_or_article_candidate_followup",
  "comparator_candidate_for_calibration_followup",
  "review_no_candidate_ready"
))
stopifnot(assessment$gate_status[[1L]] %in% c("pass", "review", "fail"))
stopifnot(assessment$total_contract_crossing_pairs[[1L]] == 0L)
stopifnot(all(app_as_bool_vec(arm_run_manifest$manifest_hashes_verified)))

resolve_phase4i_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}
for (ii in seq_len(nrow(arm_run_manifest))) {
  phase3_dir <- resolve_phase4i_path(arm_run_manifest$phase3_out_dir[[ii]])
  phase3_config <- utils::read.csv(file.path(phase3_dir, "run_config.csv"), stringsAsFactors = FALSE)
  arm_id <- arm_run_manifest$arm_id[[ii]]
  grid_row <- arm_grid[arm_grid$arm_id == arm_id, , drop = FALSE]
  stopifnot(all(phase3_config$tau0 == grid_row$tau0[[1L]]))
  stopifnot(all(phase3_config$no_future_test_leakage))
}
