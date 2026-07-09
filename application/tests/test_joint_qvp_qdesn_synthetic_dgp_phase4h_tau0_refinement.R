registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4h_ids <- c("normal_bridge", "laplace_bridge")
phase4h_base_registry <- registry[registry$scenario_id %in% phase4h_ids, , drop = FALSE]
phase4h_base_registry <- phase4h_base_registry[match(phase4h_ids, phase4h_base_registry$scenario_id), , drop = FALSE]
phase4h_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4h_base_registry$simulated_length <- 34L
phase4h_base_registry$washout_length <- 6L
phase4h_base_registry$train_length <- 18L
phase4h_base_registry$test_length <- 10L
phase4h_base_registry$seed <- c(202607081L, 202607082L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4h_base_registry)

phase4h_targeted_registry <- app_joint_qvp_phase4_build_calibration_registry(
  registry = phase4h_base_registry,
  scenario_ids = phase4h_ids,
  tier = "smoke",
  n_replicates = 1L,
  seed_base = 202607800L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L
)
stopifnot(nrow(phase4h_targeted_registry) == 2L)
stopifnot(!anyDuplicated(phase4h_targeted_registry$scenario_id))
stopifnot(length(unique(phase4h_targeted_registry$seed)) == nrow(phase4h_targeted_registry))

phase4h_grid <- app_joint_qvp_phase4h_tau0_screen_grid(c(0.25, 0.10, 0.075))
stopifnot(identical(phase4h_grid$screen_id, c("tau0_0p25_reference", "tau0_0p10_reference", "tau0_0p075")))
stopifnot(all(phase4h_grid$screen_class == "tau0_local_refinement"))
stopifnot(all(phase4h_grid$zeta2 == Inf))
stopifnot(all(phase4h_grid$alpha_prior_sd == 1))

phase4h_out <- tempfile("joint_qvp_phase4h_tau0_")
phase4h_result <- app_joint_qvp_run_synthetic_dgp_phase4h_tau0_refinement(
  out_dir = phase4h_out,
  targeted_registry_path = NULL,
  targeted_registry = phase4h_targeted_registry,
  tau0_grid = c(0.25, 0.10),
  tier = "smoke",
  vb_max_iter = 5L,
  adaptive_vb_max_iter_grid = 5L,
  refit_stride = 99L,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = 2L
)

expected_phase4h_labels <- c(
  "targeted_registry",
  "tau0_refinement_grid",
  "tau0_refinement_run_config",
  "tau0_refinement_metric_summary",
  "tau0_refinement_candidate_ranking",
  "tau0_refinement_crossing_by_scenario",
  "tau0_refinement_crossing_by_tau_pair",
  "tau0_refinement_truth_by_tau",
  "tau0_refinement_vb_runtime_summary",
  "tau0_refinement_recommendation",
  "screen_run_manifest",
  "provenance",
  "readme"
)
phase4h_manifest <- utils::read.csv(file.path(phase4h_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase4h_manifest$label, expected_phase4h_labels))
stopifnot(all(nchar(phase4h_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4h_manifest))) {
  artifact_path <- file.path(phase4h_result$out_dir, phase4h_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4h_manifest$sha256[[ii]]))
}

targeted_registry <- utils::read.csv(file.path(phase4h_result$out_dir, "targeted_registry.csv"), stringsAsFactors = FALSE)
tau0_grid <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_grid.csv"), stringsAsFactors = FALSE)
run_config <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_run_config.csv"), stringsAsFactors = FALSE)
metric_summary <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_metric_summary.csv"), stringsAsFactors = FALSE)
candidate_ranking <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_candidate_ranking.csv"), stringsAsFactors = FALSE)
crossing_by_scenario <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_crossing_by_scenario.csv"), stringsAsFactors = FALSE)
crossing_by_tau_pair <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_crossing_by_tau_pair.csv"), stringsAsFactors = FALSE)
truth_by_tau <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_truth_by_tau.csv"), stringsAsFactors = FALSE)
vb_runtime <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_vb_runtime_summary.csv"), stringsAsFactors = FALSE)
recommendation <- utils::read.csv(file.path(phase4h_result$out_dir, "tau0_refinement_recommendation.csv"), stringsAsFactors = FALSE)
screen_run_manifest <- utils::read.csv(file.path(phase4h_result$out_dir, "screen_run_manifest.csv"), stringsAsFactors = FALSE)

stopifnot(identical(targeted_registry$scenario_id, phase4h_targeted_registry$scenario_id))
stopifnot(identical(as.integer(targeted_registry$seed), as.integer(phase4h_targeted_registry$seed)))
stopifnot(identical(tau0_grid$screen_id, c("tau0_0p25_reference", "tau0_0p10_reference")))
stopifnot(run_config$phase[[1L]] == "phase4h_tau0_refinement")
stopifnot(run_config$reference_screen_id[[1L]] == "tau0_0p10_reference")
stopifnot(run_config$n_targeted_registry_rows[[1L]] == nrow(phase4h_targeted_registry))
stopifnot(run_config$n_screen_rows[[1L]] == 2L)
stopifnot(run_config$vb_max_iter[[1L]] == 5L)

stopifnot(nrow(metric_summary) == 2L)
stopifnot(all(is.finite(metric_summary$raw_crossing_pairs)))
stopifnot(all(is.finite(metric_summary$contract_crossing_pairs)))
stopifnot(all(metric_summary$contract_crossing_pairs == 0L))
stopifnot(all(is.finite(metric_summary$truth_mae_mean)))
stopifnot(all(c("screen_status", "ranking_score", "rank", "note") %in% names(candidate_ranking)))
stopifnot("reference" %in% candidate_ranking$screen_status)
stopifnot(all(c("scenario_id", "raw_crossing_pairs", "contract_crossing_pairs") %in% names(crossing_by_scenario)))
stopifnot(all(c("lower_tau", "upper_tau", "raw_crossing_pairs", "mean_true_gap") %in% names(crossing_by_tau_pair)))
stopifnot(all(is.finite(crossing_by_tau_pair$raw_crossing_pairs)))
stopifnot(all(c("tau", "mae_to_truth_mean", "n_forecasts") %in% names(truth_by_tau)))
stopifnot(all(is.finite(truth_by_tau$mae_to_truth_mean)))
stopifnot(all(is.finite(vb_runtime$runtime_total_sec)))
stopifnot(recommendation$recommendation_status[[1L]] %in% c(
  "blocked_contract_crossing",
  "candidate_ready_for_calibration_pilot",
  "reference_remains_candidate_for_calibration_pilot",
  "review_no_phase4h_candidate_ready"
))
stopifnot(all(app_as_bool_vec(screen_run_manifest$manifest_hashes_verified)))

resolve_phase4h_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}
for (ii in seq_len(nrow(screen_run_manifest))) {
  phase3_dir <- resolve_phase4h_path(screen_run_manifest$phase3_out_dir[[ii]])
  phase3_config <- utils::read.csv(file.path(phase3_dir, "run_config.csv"), stringsAsFactors = FALSE)
  screen_id <- screen_run_manifest$screen_id[[ii]]
  grid_row <- tau0_grid[tau0_grid$screen_id == screen_id, , drop = FALSE]
  stopifnot(all(phase3_config$tau0 == grid_row$tau0[[1L]]))
}
