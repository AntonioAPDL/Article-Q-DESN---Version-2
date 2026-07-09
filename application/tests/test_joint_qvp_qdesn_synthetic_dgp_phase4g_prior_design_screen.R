registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4g_ids <- c("normal_bridge", "laplace_bridge")
phase4g_base_registry <- registry[registry$scenario_id %in% phase4g_ids, , drop = FALSE]
phase4g_base_registry <- phase4g_base_registry[match(phase4g_ids, phase4g_base_registry$scenario_id), , drop = FALSE]
phase4g_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4g_base_registry$simulated_length <- 34L
phase4g_base_registry$washout_length <- 6L
phase4g_base_registry$train_length <- 18L
phase4g_base_registry$test_length <- 10L
phase4g_base_registry$seed <- c(202607071L, 202607072L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4g_base_registry)

phase4g_targeted_registry <- app_joint_qvp_phase4_build_calibration_registry(
  registry = phase4g_base_registry,
  scenario_ids = phase4g_ids,
  tier = "smoke",
  n_replicates = 1L,
  seed_base = 202607700L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L
)
stopifnot(nrow(phase4g_targeted_registry) == 2L)
stopifnot(!anyDuplicated(phase4g_targeted_registry$scenario_id))
stopifnot(length(unique(phase4g_targeted_registry$seed)) == nrow(phase4g_targeted_registry))

phase4g_grid <- app_joint_qvp_phase4g_screen_grid("targeted")
stopifnot(all(c("baseline_vb480", "tau0_0p5", "zeta2_10", "rhs_inner_8") %in% phase4g_grid$screen_id))
stopifnot(phase4g_grid$tau0[phase4g_grid$screen_id == "tau0_0p5"] == 0.5)
stopifnot(phase4g_grid$zeta2[phase4g_grid$screen_id == "zeta2_10"] == 10)
stopifnot(phase4g_grid$rhs_vb_inner[phase4g_grid$screen_id == "rhs_inner_8"] == 8L)

phase4g_out <- tempfile("joint_qvp_phase4g_screen_")
phase4g_result <- app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen(
  out_dir = phase4g_out,
  targeted_registry_path = NULL,
  targeted_registry = phase4g_targeted_registry,
  tier = "smoke",
  screen_ids = c("baseline_vb480", "tau0_0p5", "zeta2_10"),
  vb_max_iter = 5L,
  adaptive_vb_max_iter_grid = 5L,
  refit_stride = 99L,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = 2L
)

expected_phase4g_labels <- c(
  "targeted_registry",
  "screen_grid",
  "screen_run_config",
  "screen_metric_summary",
  "screen_candidate_ranking",
  "screen_crossing_summary",
  "screen_truth_metric_summary",
  "screen_vb_runtime_summary",
  "screen_run_manifest",
  "screen_recommendation",
  "provenance",
  "readme"
)
phase4g_manifest <- utils::read.csv(file.path(phase4g_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4g_manifest$label, expected_phase4g_labels))
stopifnot(all(nchar(phase4g_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4g_manifest))) {
  artifact_path <- file.path(phase4g_result$out_dir, phase4g_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4g_manifest$sha256[[ii]]))
}

targeted_registry <- utils::read.csv(file.path(phase4g_result$out_dir, "targeted_registry.csv"), stringsAsFactors = FALSE)
screen_grid <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_grid.csv"), stringsAsFactors = FALSE)
screen_run_config <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_run_config.csv"), stringsAsFactors = FALSE)
screen_metric_summary <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_metric_summary.csv"), stringsAsFactors = FALSE)
screen_candidate_ranking <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_candidate_ranking.csv"), stringsAsFactors = FALSE)
screen_crossing_summary <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_crossing_summary.csv"), stringsAsFactors = FALSE)
screen_truth_metric_summary <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_truth_metric_summary.csv"), stringsAsFactors = FALSE)
screen_vb_runtime_summary <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_vb_runtime_summary.csv"), stringsAsFactors = FALSE)
screen_run_manifest <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_run_manifest.csv"), stringsAsFactors = FALSE)
screen_recommendation <- utils::read.csv(file.path(phase4g_result$out_dir, "screen_recommendation.csv"), stringsAsFactors = FALSE)

stopifnot(identical(targeted_registry$scenario_id, phase4g_targeted_registry$scenario_id))
stopifnot(identical(as.integer(targeted_registry$seed), as.integer(phase4g_targeted_registry$seed)))
stopifnot(identical(screen_grid$screen_id, c("baseline_vb480", "tau0_0p5", "zeta2_10")))
stopifnot(screen_run_config$tier[[1L]] == "smoke")
stopifnot(screen_run_config$n_targeted_registry_rows[[1L]] == nrow(phase4g_targeted_registry))
stopifnot(screen_run_config$n_screen_rows[[1L]] == 3L)
stopifnot(screen_run_config$vb_max_iter[[1L]] == 5L)
stopifnot(screen_run_config$adaptive_vb_max_iter_grid[[1L]] == "5")
stopifnot(screen_run_config$all_phase3_manifest_hashes_verified[[1L]])

stopifnot(all(c(
  "screen_id", "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner",
  "raw_crossing_pairs", "contract_crossing_pairs", "truth_mae_mean",
  "max_abs_hit_rate_error", "vb_max_iter_rate", "runtime_total_sec"
) %in% names(screen_metric_summary)))
stopifnot(nrow(screen_metric_summary) == 3L)
stopifnot(all(is.finite(screen_metric_summary$truth_mae_mean)))
stopifnot(all(is.finite(screen_metric_summary$max_abs_hit_rate_error)))
stopifnot(all(is.finite(screen_metric_summary$raw_crossing_pairs)))
stopifnot(all(is.finite(screen_metric_summary$contract_crossing_pairs)))
stopifnot(all(screen_metric_summary$contract_crossing_pairs == 0L))
stopifnot(all(screen_metric_summary$n_scenarios == nrow(phase4g_targeted_registry)))
stopifnot(all(screen_metric_summary$n_forecast_origins == 2L * nrow(phase4g_targeted_registry)))

stopifnot(all(c("screen_status", "ranking_score", "rank", "note") %in% names(screen_candidate_ranking)))
stopifnot("reference" %in% screen_candidate_ranking$screen_status)
stopifnot(all(screen_candidate_ranking$screen_status %in% c("reference", "review", "fail", "promote_to_calibration_pilot")))
stopifnot(all(screen_crossing_summary$contract_crossing_pairs == 0L))
stopifnot(all(is.finite(screen_truth_metric_summary$truth_mae_mean)))
stopifnot(all(is.finite(screen_vb_runtime_summary$runtime_total_sec)))
stopifnot(all(app_as_bool_vec(screen_run_manifest$manifest_hashes_verified)))
stopifnot(screen_recommendation$recommendation_status[[1L]] %in% c(
  "promote_best_to_calibration_pilot",
  "blocked_contract_crossing",
  "no_promoted_candidate_keep_contract_policy_or_expand_tier2"
))

resolve_phase4g_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}
for (ii in seq_len(nrow(screen_run_manifest))) {
  phase3_dir <- resolve_phase4g_path(screen_run_manifest$phase3_out_dir[[ii]])
  phase3_config <- utils::read.csv(file.path(phase3_dir, "run_config.csv"), stringsAsFactors = FALSE)
  screen_id <- screen_run_manifest$screen_id[[ii]]
  grid_row <- screen_grid[screen_grid$screen_id == screen_id, , drop = FALSE]
  stopifnot(all(phase3_config$tau0 == grid_row$tau0[[1L]]))
  stopifnot(all(phase3_config$alpha_prior_sd == grid_row$alpha_prior_sd[[1L]]))
  stopifnot(all(phase3_config$alpha_min_spacing == grid_row$alpha_min_spacing[[1L]]))
  stopifnot(all(phase3_config$rhs_vb_inner == grid_row$rhs_vb_inner[[1L]]))
  if (is.infinite(grid_row$zeta2[[1L]])) {
    stopifnot(all(is.infinite(phase3_config$zeta2)))
  } else {
    stopifnot(all(phase3_config$zeta2 == grid_row$zeta2[[1L]]))
  }
}
