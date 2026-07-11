repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 120 test.", call. = FALSE)
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
source(app_path("application/R/joint_qdesn_calibration_screening.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  invisible(manifest)
}

metric_row <- function(candidate_id, model_id, display_label, likelihood, fit_structure, truth_mae,
                       raw_crossing_pairs, reached_max_iter, stage = "forecast") {
  data.frame(
    candidate_id = candidate_id,
    candidate_label = candidate_id,
    candidate_role = if (grepl("selected_controls", candidate_id, fixed = TRUE)) "case_selected_controls_reference" else "case_candidate",
    tau0 = 0.5,
    zeta2 = 16,
    alpha_prior_sd = "0.5",
    alpha_min_spacing = 0,
    gamma_init_policy = "zero",
    scenario_ids = sub("__.*$", "", candidate_id),
    model_ids = model_id,
    vb_max_iter = 1440L,
    adaptive_vb_max_iter_grid = "1440,1920",
    rhs_vb_inner = 10L,
    stage = stage,
    model_id = model_id,
    display_label = display_label,
    likelihood = likelihood,
    fit_structure = fit_structure,
    truth_mae = truth_mae,
    truth_sq_error = truth_mae^2,
    truth_rmse = truth_mae * 1.2,
    check_loss_mean = truth_mae + 0.05,
    crps_grid_mean = truth_mae + 0.20,
    abs_hit_rate_error = 0.02,
    abs_coverage_error = 0.03,
    interval_width_mean = 1.0,
    interval_score_mean = 1.2,
    raw_crossing_pairs = raw_crossing_pairs,
    contract_crossing_pairs = 0,
    reached_max_iter = reached_max_iter,
    elapsed_seconds = 12,
    max_abs_adjustment = if (raw_crossing_pairs > 0) 0.02 else 0,
    adjustment_rate = if (raw_crossing_pairs > 0) 0.01 else 0,
    finite_quantiles = TRUE,
    finite_scores = TRUE,
    gate_status = if (raw_crossing_pairs > 0 || reached_max_iter > 0) "review" else "pass",
    stringsAsFactors = FALSE
  )
}

registry_row <- function(candidate_id, model_id, case_id, scenario_id, role, shard_dir) {
  data.frame(
    candidate_id = candidate_id,
    candidate_label = candidate_id,
    use_existing_artifacts = FALSE,
    fit_dir = file.path(shard_dir, "candidates", candidate_id, "fit"),
    forecast_dir = file.path(shard_dir, "candidates", candidate_id, "forecast"),
    vb_max_iter = 1440L,
    adaptive_vb_max_iter_grid = "1440,1920",
    vb_tol = 1.0e-4,
    rhs_vb_inner = 10L,
    tau0 = 0.5,
    zeta2 = 16,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd = "0.5",
    alpha_min_spacing = 0,
    gamma_init_policy = "zero",
    review_adjustment_threshold = 1.0e-3,
    max_dense_dim = 300L,
    n_cores = 1L,
    candidate_role = role,
    notes = "test row",
    scenario_ids = scenario_id,
    model_ids = model_id,
    case_id = case_id,
    case_priority = "high",
    case_focus = if (grepl("exqdesn", model_id, fixed = TRUE)) "joint_exal_tail_fan" else "primary_joint_al_accuracy",
    case_current_forecast_truth_mae = 0.2,
    case_gap_vs_best_al = 0,
    stringsAsFactors = FALSE
  )
}

write_shard <- function(dir, rows) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  registry <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "registry"))
  health <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "health"))
  fit <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "fit"))
  forecast <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "forecast"))
  nested <- data.frame(
    candidate_id = registry$candidate_id,
    stage = "fit",
    label = "artifact_manifest",
    relative_path = "artifact_manifest.csv",
    path = file.path(registry$fit_dir, "artifact_manifest.csv"),
    exists = TRUE,
    declared_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    actual_sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    declared_size_bytes = 1,
    actual_size_bytes = 1,
    status = "pass",
    stringsAsFactors = FALSE
  )
  paths <- c(
    candidate_registry = app_joint_qdesn_screening_write_csv(registry, file.path(dir, "candidate_registry.csv")),
    screening_health_summary = app_joint_qdesn_screening_write_csv(health, file.path(dir, "screening_health_summary.csv")),
    fit_model_metric_summary = app_joint_qdesn_screening_write_csv(fit, file.path(dir, "fit_model_metric_summary.csv")),
    forecast_model_metric_summary = app_joint_qdesn_screening_write_csv(forecast, file.path(dir, "forecast_model_metric_summary.csv")),
    candidate_manifest_verification = app_joint_qdesn_screening_write_csv(nested, file.path(dir, "candidate_manifest_verification.csv"))
  )
  invisible(app_joint_qdesn_write_manifest(paths, dir))
}

tmp_root <- tempfile("joint_qdesn_phase120_")
al_dir <- file.path(tmp_root, "al_high_priority")
exal_dir <- file.path(tmp_root, "exal_high_priority")
out_dir <- file.path(tmp_root, "phase120")
screen_dir <- file.path(tmp_root, "screening")

al_rows <- list(
  list(
    registry = registry_row("normal_bridge__qdesn_rhs_independent_vb__selected_controls", "qdesn_rhs_independent_vb", "normal_bridge__qdesn_rhs_independent_vb", "normal_bridge", "case_selected_controls_reference", al_dir),
    health = data.frame(candidate_id = "normal_bridge__qdesn_rhs_independent_vb__selected_controls", candidate_label = "ref", manifest_status = "pass", fit_models = 1, forecast_models = 1, scenario_worker_failures = 0, fit_worker_failures = 0, forecast_worker_failures = 0, fit_fail_models = 0, forecast_fail_models = 0, fit_raw_crossings = 0, forecast_raw_crossings = 8, contract_crossings = 0, max_forecast_adjustment = 0.02, max_forecast_truth_mae = 0.12, catastrophic_rows = 0, fit_reached_max_iter = 0, forecast_reached_max_iter = 1, elapsed_seconds = 24, gate_status = "review", stringsAsFactors = FALSE),
    fit = metric_row("normal_bridge__qdesn_rhs_independent_vb__selected_controls", "qdesn_rhs_independent_vb", "QDESN RHS", "al", "independent_single_tau", 0.10, 0, 0, "fit"),
    forecast = metric_row("normal_bridge__qdesn_rhs_independent_vb__selected_controls", "qdesn_rhs_independent_vb", "QDESN RHS", "al", "independent_single_tau", 0.12, 8, 1, "forecast")
  ),
  list(
    registry = registry_row("laplace_bridge__joint_qdesn_rhs_vb__selected_controls", "joint_qdesn_rhs_vb", "laplace_bridge__joint_qdesn_rhs_vb", "laplace_bridge", "case_selected_controls_reference", al_dir),
    health = data.frame(candidate_id = "laplace_bridge__joint_qdesn_rhs_vb__selected_controls", candidate_label = "pass", manifest_status = "pass", fit_models = 1, forecast_models = 1, scenario_worker_failures = 0, fit_worker_failures = 0, forecast_worker_failures = 0, fit_fail_models = 0, forecast_fail_models = 0, fit_raw_crossings = 0, forecast_raw_crossings = 0, contract_crossings = 0, max_forecast_adjustment = 0, max_forecast_truth_mae = 0.08, catastrophic_rows = 0, fit_reached_max_iter = 0, forecast_reached_max_iter = 0, elapsed_seconds = 20, gate_status = "pass", stringsAsFactors = FALSE),
    fit = metric_row("laplace_bridge__joint_qdesn_rhs_vb__selected_controls", "joint_qdesn_rhs_vb", "JOINT QDESN RHS", "al", "joint", 0.07, 0, 0, "fit"),
    forecast = metric_row("laplace_bridge__joint_qdesn_rhs_vb__selected_controls", "joint_qdesn_rhs_vb", "JOINT QDESN RHS", "al", "joint", 0.08, 0, 0, "forecast")
  )
)

exal_rows <- list(
  list(
    registry = registry_row("asymmetric_laplace_tail__joint_exqdesn_rhs_vb__selected_controls", "joint_exqdesn_rhs_vb", "asymmetric_laplace_tail__joint_exqdesn_rhs_vb", "asymmetric_laplace_tail", "case_selected_controls_reference", exal_dir),
    health = data.frame(candidate_id = "asymmetric_laplace_tail__joint_exqdesn_rhs_vb__selected_controls", candidate_label = "exal", manifest_status = "pass", fit_models = 1, forecast_models = 1, scenario_worker_failures = 0, fit_worker_failures = 0, forecast_worker_failures = 0, fit_fail_models = 0, forecast_fail_models = 0, fit_raw_crossings = 0, forecast_raw_crossings = 0, contract_crossings = 0, max_forecast_adjustment = 0, max_forecast_truth_mae = 0.14, catastrophic_rows = 0, fit_reached_max_iter = 0, forecast_reached_max_iter = 1, elapsed_seconds = 30, gate_status = "review", stringsAsFactors = FALSE),
    fit = metric_row("asymmetric_laplace_tail__joint_exqdesn_rhs_vb__selected_controls", "joint_exqdesn_rhs_vb", "JOINT exQDESN RHS", "exal", "joint", 0.11, 0, 0, "fit"),
    forecast = metric_row("asymmetric_laplace_tail__joint_exqdesn_rhs_vb__selected_controls", "joint_exqdesn_rhs_vb", "JOINT exQDESN RHS", "exal", "joint", 0.14, 0, 1, "forecast")
  )
)

write_shard(al_dir, al_rows)
write_shard(exal_dir, exal_rows)

result <- app_joint_qdesn_run_phase120_case_selection_followup(
  out_dir = out_dir,
  screening_output_dir = screen_dir,
  al_high_priority_dir = al_dir,
  exal_high_priority_dir = exal_dir,
  fixture_dir = tempfile("joint_qdesn_phase120_fixture_"),
  n_cores = 1L
)

check_manifest(result$out_dir)
stopifnot(identical(result$run_config$readiness_decision[[1L]], "ready_to_launch_phase120_targeted_followup"))
stopifnot(nrow(result$case_winners) == 3L)
stopifnot(nrow(result$targets) == 2L)
stopifnot(nrow(result$registry) == 12L)
stopifnot(!anyDuplicated(result$registry$candidate_id))
stopifnot(all(result$registry$case_priority == "phase120_targeted_followup"))
stopifnot(all(nzchar(result$registry$phase120_source_best_candidate_id)))
app_joint_qdesn_validate_screening_registry(result$registry, allow_alpha_prior_vectors = FALSE)
stopifnot(any(result$case_winners$followup_status == "ready_for_vb_freeze_candidate"))
stopifnot(any(result$case_winners$followup_status == "review_followup_raw_crossing"))
stopifnot(any(result$case_winners$followup_status == "review_followup_convergence"))
stopifnot(any(grepl("123_launch_joint_qdesn_screening_parallel_chunks.sh", result$launch_commands$command, fixed = TRUE)))
stopifnot(any(grepl("--registry", result$launch_commands$command, fixed = TRUE)))

cat("Joint QDESN Phase 120 case-selection follow-up test passed.\n")
