repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN article-readiness audit test.", call. = FALSE)
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
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_article_assets.R"))
source(app_path("application/R/joint_qdesn_article_readiness_audit.R"))

write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

check_manifest <- function(dir) {
  manifest <- app_read_csv(file.path(dir, "artifact_manifest.csv"))
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  manifest
}

write_manifest <- function(paths, dir) {
  info <- app_joint_qdesn_write_manifest(paths, dir)
  stopifnot(file.exists(info$manifest_path))
  invisible(check_manifest(dir))
}

phase113_dir <- tempfile("joint_qdesn_phase113_readiness_")
phase114_freeze_dir <- tempfile("joint_qdesn_phase114_freeze_readiness_")
phase114_mcmc_dir <- tempfile("joint_qdesn_phase114_mcmc_readiness_")
phase115_dir <- tempfile("joint_qdesn_phase115_readiness_")
out_dir <- tempfile("joint_qdesn_phase116_readiness_")
app_ensure_dir(phase113_dir)
app_ensure_dir(phase114_freeze_dir)
app_ensure_dir(phase114_mcmc_dir)
app_ensure_dir(phase115_dir)

candidate_id <- "zeta2_16_inner10_gamma_zero_alpha0p5_tau0_0p5"
scenario_ids <- c("normal_bridge", "persistent_heavy_tail")
model_ids <- c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb", "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")
labels <- c("JOINT QDESN RHS", "QDESN RHS", "JOINT exQDESN RHS", "exQDESN RHS")

scenario_rows <- do.call(rbind, lapply(scenario_ids, function(sid) {
  data.frame(
    candidate_id = candidate_id,
    scenario_id = sid,
    model_id = model_ids,
    display_label = labels,
    truth_mae = c(0.09, 0.11, 0.13, 0.14) + ifelse(sid == "persistent_heavy_tail", 0.02, 0),
    check_loss_mean = c(0.13, 0.14, 0.15, 0.16),
    raw_crossing_pairs = c(1L, 2L, 0L, 3L),
    contract_crossing_pairs = 0L,
    reached_max_iter = c(FALSE, TRUE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
}))
tau_rows <- do.call(rbind, lapply(c(0.05, 0.50, 0.95), function(tt) {
  data.frame(
    candidate_id = candidate_id,
    tau = tt,
    model_id = model_ids,
    display_label = labels,
    truth_mae = c(0.10, 0.12, 0.16, 0.15) + ifelse(tt %in% c(0.05, 0.95), 0.03, 0),
    stringsAsFactors = FALSE
  )
}))

phase113_paths <- c(
  selected_spec_recommendation = write_csv(data.frame(
    candidate_id = candidate_id,
    candidate_label = "Selected fixture candidate",
    gate_status = "review",
    screening_score = 0.27,
    mean_fit_truth_mae = 0.11,
    mean_forecast_truth_mae = 0.12,
    joint_qdesn_forecast_truth_mae = 0.096,
    independent_exqdesn_forecast_truth_mae = 0.133,
    max_scenario_forecast_truth_mae = 0.20,
    forecast_raw_crossings = 73L,
    max_forecast_adjustment = 0.23,
    elapsed_minutes = 1,
    recommendation_class = "usable_with_review",
    rank = 1L,
    selected = TRUE,
    next_action = "review",
    stringsAsFactors = FALSE
  ), file.path(phase113_dir, "selected_spec_recommendation.csv")),
  screening_health_summary = write_csv(data.frame(
    candidate_id = candidate_id,
    candidate_label = "Selected fixture candidate",
    manifest_status = "pass",
    forecast_raw_crossings = 73L,
    contract_crossings = 0L,
    max_forecast_adjustment = 0.23,
    max_forecast_truth_mae = 0.20,
    fit_reached_max_iter = 0L,
    forecast_reached_max_iter = 1L,
    gate_status = "review",
    stringsAsFactors = FALSE
  ), file.path(phase113_dir, "screening_health_summary.csv")),
  candidate_scorecard = write_csv(data.frame(candidate_id = candidate_id, rank = 1L, gate_status = "review", stringsAsFactors = FALSE), file.path(phase113_dir, "candidate_scorecard.csv")),
  forecast_model_metric_summary = write_csv(data.frame(candidate_id = candidate_id, model_id = model_ids, display_label = labels, raw_crossing_pairs = c(1L, 2L, 0L, 3L), contract_crossing_pairs = 0L, gate_status = "review", stringsAsFactors = FALSE), file.path(phase113_dir, "forecast_model_metric_summary.csv")),
  forecast_scenario_metric_summary = write_csv(scenario_rows, file.path(phase113_dir, "forecast_scenario_metric_summary.csv")),
  forecast_tau_metric_summary = write_csv(tau_rows, file.path(phase113_dir, "forecast_tau_metric_summary.csv"))
)
candidate_manifest <- data.frame(
  candidate_id = candidate_id,
  stage = "forecast",
  label = "forecast_scenario_metric_summary",
  relative_path = "forecast_scenario_metric_summary.csv",
  path = phase113_paths[["forecast_scenario_metric_summary"]],
  exists = TRUE,
  declared_sha256 = app_sha256_file(phase113_paths[["forecast_scenario_metric_summary"]]),
  actual_sha256 = app_sha256_file(phase113_paths[["forecast_scenario_metric_summary"]]),
  declared_size_bytes = as.numeric(file.info(phase113_paths[["forecast_scenario_metric_summary"]])$size),
  actual_size_bytes = as.numeric(file.info(phase113_paths[["forecast_scenario_metric_summary"]])$size),
  status = "pass",
  stringsAsFactors = FALSE
)
phase113_paths[["candidate_manifest_verification"]] <- write_csv(candidate_manifest, file.path(phase113_dir, "candidate_manifest_verification.csv"))
write_manifest(phase113_paths, phase113_dir)

phase114_freeze_paths <- c(
  freeze_decision_summary = write_csv(data.frame(
    freeze_id = "test",
    selected_candidate_id = candidate_id,
    freeze_status = "review_ready_for_mcmc_initialization",
    decision = "freeze_selected_vb_candidate_and_launch_vb_initialized_mcmc_article_candidate",
    stringsAsFactors = FALSE
  ), file.path(phase114_freeze_dir, "freeze_decision_summary.csv")),
  freeze_gate_audit = write_csv(data.frame(gate = "contract_crossings", status = "pass", detail = "0", stringsAsFactors = FALSE), file.path(phase114_freeze_dir, "freeze_gate_audit.csv")),
  phase114_launch_plan = write_csv(data.frame(command_id = "mcmc", command = "Rscript ...", purpose = "test", stringsAsFactors = FALSE), file.path(phase114_freeze_dir, "phase114_launch_plan.csv"))
)
write_manifest(phase114_freeze_paths, phase114_freeze_dir)

mcmc_summary <- data.frame(
  scenario_id = scenario_ids,
  distribution_family = c("gaussian", "student_t"),
  dynamics_class = c("ar1", "persistent"),
  vb_truth_mae = c(0.08, 0.12),
  mcmc_truth_mae = c(0.081, 0.121),
  vb_mcmc_max_normalized_distance = c(0.10, 0.18),
  max_chain_to_pooled_normalized_distance = c(0.12, 0.19),
  mcmc_n_keep_total = 120L,
  mcmc_raw_crossing_pairs = 0L,
  mcmc_contract_crossing_pairs = 0L,
  total_elapsed_seconds = c(10, 11),
  stringsAsFactors = FALSE
)
phase114_mcmc_paths <- c(
  mcmc_readiness_assessment = write_csv(data.frame(
    scenario_id = scenario_ids,
    gate_status = "pass",
    status_reason = "all readiness gates passed",
    stringsAsFactors = FALSE
  ), file.path(phase114_mcmc_dir, "mcmc_readiness_assessment.csv")),
  mcmc_readiness_summary = write_csv(mcmc_summary, file.path(phase114_mcmc_dir, "mcmc_readiness_summary.csv")),
  vb_mcmc_distance_summary = write_csv(data.frame(scenario_id = scenario_ids, max_normalized_distance = c(0.10, 0.18), stringsAsFactors = FALSE), file.path(phase114_mcmc_dir, "vb_mcmc_distance_summary.csv")),
  chain_to_pooled_distance_summary = write_csv(data.frame(scenario_id = scenario_ids, max_normalized_to_pooled = c(0.12, 0.19), stringsAsFactors = FALSE), file.path(phase114_mcmc_dir, "chain_to_pooled_distance_summary.csv")),
  scenario_worker_failures = write_csv(data.frame(validation_label = character(), scenario_id = character(), worker_index = integer(), worker_status = character(), error_class = character(), error_message = character(), stringsAsFactors = FALSE), file.path(phase114_mcmc_dir, "scenario_worker_failures.csv"))
)
write_manifest(phase114_mcmc_paths, phase114_mcmc_dir)

asset_file <- write_csv(data.frame(x = 1), file.path(tempdir(), "joint_qdesn_phase116_asset.csv"))
asset_manifest <- data.frame(
  label = "test_asset",
  artifact_type = "csv_table",
  path = asset_file,
  size_bytes = as.numeric(file.info(asset_file)$size),
  sha256 = app_sha256_file(asset_file),
  stringsAsFactors = FALSE
)
phase115_paths <- c(
  article_readiness_assessment = write_csv(data.frame(
    overall_gate = "review",
    vb_source_gate = "review",
    mcmc_reference_gate = "pass",
    selected_candidate = candidate_id,
    vb_source_forecast_raw_crossings = 73L,
    vb_source_forecast_contract_crossings = 0L,
    mcmc_worker_failures = 0L,
    mcmc_contract_crossings = 0L,
    mcmc_raw_crossings = 0L,
    mcmc_review_scenarios = "",
    recommended_next_action = "Use assets with review language.",
    stringsAsFactors = FALSE
  ), file.path(phase115_dir, "article_readiness_assessment.csv")),
  gate_summary = write_csv(data.frame(Evidence = "Source manifests", Gate = "pass", Detail = "test", stringsAsFactors = FALSE), file.path(phase115_dir, "gate_summary.csv")),
  source_manifest_verification = write_csv(data.frame(artifact_label = "test", label = "test", status = "pass", stringsAsFactors = FALSE), file.path(phase115_dir, "source_manifest_verification.csv")),
  article_asset_manifest = write_csv(asset_manifest, file.path(phase115_dir, "article_asset_manifest.csv"))
)
write_manifest(phase115_paths, phase115_dir)

result <- app_joint_qdesn_run_phase116_article_readiness_audit(
  out_dir = out_dir,
  phase113_dir = phase113_dir,
  phase114_freeze_dir = phase114_freeze_dir,
  phase114_mcmc_dir = phase114_mcmc_dir,
  phase115_dir = phase115_dir
)

manifest <- check_manifest(result$out_dir)
stopifnot(result$decision$overall_gate[[1L]] == "review")
stopifnot(identical(result$decision$wait_required[[1L]], FALSE))
stopifnot(identical(result$decision$new_broad_vb_screen_recommended[[1L]], FALSE))
stopifnot(result$decision$selected_candidate[[1L]] == candidate_id)
stopifnot(nrow(result$health) == 6L)
stopifnot(any(result$health$component == "Phase 114 MCMC reference"))
stopifnot(nrow(result$scenario_sensitivity) == length(scenario_ids))
stopifnot(nrow(result$tau_sensitivity) == 3L)
stopifnot(all(result$distance_focus$distance_gate == "pass"))
stopifnot(any(result$claim_audit$claim_or_decision == "Treat MCMC as fit-window reference, not forecast validation"))
stopifnot("readiness_decision_summary" %in% manifest$label)
stopifnot(file.exists(file.path(result$out_dir, "README.md")))
