repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN MCMC readiness test.", call. = FALSE)
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
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  manifest
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
small$seed <- 202607242L
app_joint_qdesn_validate_simulation_registry(small)

fixture_dir <- tempfile("joint_qdesn_mcmc_fixture_")
fixture <- app_joint_qdesn_materialize_simulation_fixtures(
  out_dir = fixture_dir,
  registry = small,
  registry_path = app_joint_qdesn_default_simulation_registry_path()
)
stopifnot(all(fixture$fixture_validation$status == "pass"))
fixture_manifest <- check_manifest(fixture$out_dir)
stopifnot(nrow(fixture_manifest) > 0L)

phase107_dir <- tempfile("joint_qdesn_phase107_contract_")
app_ensure_dir(phase107_dir)
candidate <- app_joint_qdesn_default_vb_spec_screening_registry(out_dir = phase107_dir, n_cores = 1L)
candidate <- candidate[candidate$candidate_id == "rhs_tau0_0p5_alpha0p5", , drop = FALSE]
candidate$vb_max_iter <- 1L
candidate$adaptive_vb_max_iter_grid <- "1"
candidate$rhs_vb_inner <- 1L
candidate$n_cores <- 1L
candidate$fit_dir <- file.path(phase107_dir, "fit")
candidate$forecast_dir <- file.path(phase107_dir, "forecast")
selected <- data.frame(
  candidate_id = candidate$candidate_id,
  candidate_label = candidate$candidate_label,
  gate_status = "review",
  screening_score = 1,
  mean_fit_truth_mae = 0,
  mean_forecast_truth_mae = 0,
  joint_qdesn_forecast_truth_mae = 0,
  independent_exqdesn_forecast_truth_mae = 0,
  max_scenario_forecast_truth_mae = 0,
  forecast_raw_crossings = 0L,
  max_forecast_adjustment = 0,
  elapsed_minutes = 0,
  recommendation_class = "test_contract",
  rank = 1L,
  selected = TRUE,
  next_action = "test",
  stringsAsFactors = FALSE
)
nested <- data.frame(
  candidate_id = candidate$candidate_id,
  stage = "fit",
  label = "test_nested_manifest",
  relative_path = "candidate_registry.csv",
  path = normalizePath(file.path(phase107_dir, "candidate_registry.csv"), mustWork = FALSE),
  exists = TRUE,
  declared_sha256 = NA_character_,
  actual_sha256 = NA_character_,
  declared_size_bytes = NA_real_,
  actual_size_bytes = NA_real_,
  status = "pass",
  stringsAsFactors = FALSE
)
candidate_path <- app_joint_qvp_write_csv(candidate, file.path(phase107_dir, "candidate_registry.csv"))
selected_path <- app_joint_qvp_write_csv(selected, file.path(phase107_dir, "selected_spec_recommendation.csv"))
nested$declared_sha256[[1L]] <- app_sha256_file(candidate_path)
nested$actual_sha256[[1L]] <- nested$declared_sha256[[1L]]
nested$declared_size_bytes[[1L]] <- as.numeric(file.info(candidate_path)$size)
nested$actual_size_bytes[[1L]] <- nested$declared_size_bytes[[1L]]
nested_path <- app_joint_qvp_write_csv(nested, file.path(phase107_dir, "candidate_manifest_verification.csv"))
phase107_manifest_info <- app_joint_qdesn_write_manifest(c(
  candidate_registry = candidate_path,
  selected_spec_recommendation = selected_path,
  candidate_manifest_verification = nested_path
), phase107_dir)
stopifnot(file.exists(phase107_manifest_info$manifest_path))
phase107_manifest <- check_manifest(phase107_dir)
stopifnot(nrow(phase107_manifest) > 0L)

out_dir <- tempfile("joint_qdesn_mcmc_readiness_")
result <- app_joint_qdesn_run_mcmc_readiness(
  out_dir = out_dir,
  fixture_dir = fixture$out_dir,
  phase107_dir = phase107_dir,
  scenario_ids = "normal_bridge",
  n_chains = 2L,
  mcmc_n_iter = 12L,
  mcmc_burn = 6L,
  mcmc_thin = 3L,
  n_cores = 1L
)

manifest <- check_manifest(result$out_dir)
expected_labels <- c(
  "run_config",
  "phase107_source_manifest_verification",
  "fixture_source_manifest",
  "scenario_worker_failures",
  "mcmc_readiness_summary",
  "mcmc_readiness_assessment",
  "fit_quantiles_raw",
  "fit_quantiles",
  "fit_monotone_adjustment",
  "fit_truth_comparison",
  "truth_distance_summary",
  "check_loss_summary",
  "hit_rate_summary",
  "crps_grid_summary",
  "interval_summary",
  "crossing_summary",
  "raw_crossing_summary",
  "vb_convergence_audit",
  "objective_diagnostics",
  "rhs_prior_summary",
  "scale_parameter_summary",
  "mcmc_draw_summary",
  "vb_mcmc_distance_summary",
  "chain_to_pooled_distance_summary",
  "runtime_summary",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected_labels))

summary <- utils::read.csv(file.path(result$out_dir, "mcmc_readiness_summary.csv"), stringsAsFactors = FALSE)
assessment <- utils::read.csv(file.path(result$out_dir, "mcmc_readiness_assessment.csv"), stringsAsFactors = FALSE)
draw_summary <- utils::read.csv(file.path(result$out_dir, "mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
distance <- utils::read.csv(file.path(result$out_dir, "vb_mcmc_distance_summary.csv"), stringsAsFactors = FALSE)
crossing <- utils::read.csv(file.path(result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
failures <- utils::read.csv(file.path(result$out_dir, "scenario_worker_failures.csv"), stringsAsFactors = FALSE)

stopifnot(nrow(summary) == 1L)
stopifnot(summary$mcmc_init_source[[1L]] == "provided")
stopifnot(summary$all_chain_init_source_provided[[1L]])
stopifnot(summary$mcmc_draws_all_finite[[1L]])
stopifnot(summary$mcmc_n_keep_total[[1L]] == 4L)
stopifnot(summary$mcmc_contract_crossing_pairs[[1L]] == 0L)
stopifnot(all(is.finite(summary$vb_mcmc_max_normalized_distance)))
stopifnot(all(is.finite(summary$max_chain_to_pooled_normalized_distance)))
stopifnot(nrow(assessment) == 1L)
stopifnot(assessment$implementation_status[[1L]] == "pass")
stopifnot(assessment$gate_status[[1L]] %in% c("pass", "review"))
stopifnot(nrow(failures) == 0L)
stopifnot(all(draw_summary$all_finite))
stopifnot(all(draw_summary$n_draws == 2L))
stopifnot(identical(sort(unique(draw_summary$block)), c("alpha", "beta", "sigma")))
stopifnot(all(is.finite(distance$max_normalized_distance)))
stopifnot(sum(crossing$n_crossing_pairs) == 0L)
