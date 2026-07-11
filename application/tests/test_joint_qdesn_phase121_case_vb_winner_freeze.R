repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 121 test.", call. = FALSE)
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
                       raw_crossing_pairs = 0L, reached_max_iter = 0L, stage = "forecast") {
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

registry_row <- function(candidate_id, model_id, case_id, scenario_id, role, shard_dir, likelihood = "al",
                         fit_structure = "joint") {
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
    notes = paste(likelihood, fit_structure, "test row"),
    scenario_ids = scenario_id,
    model_ids = model_id,
    case_id = case_id,
    case_priority = "high",
    case_focus = "test_case",
    case_current_forecast_truth_mae = 0.2,
    case_gap_vs_best_al = 0,
    stringsAsFactors = FALSE
  )
}

health_row <- function(candidate_id, raw_crossings = 0L, reached_max_iter = 0L, truth_mae = 0.1) {
  data.frame(
    candidate_id = candidate_id,
    candidate_label = candidate_id,
    manifest_status = "pass",
    fit_models = 1,
    forecast_models = 1,
    scenario_worker_failures = 0,
    fit_worker_failures = 0,
    forecast_worker_failures = 0,
    fit_fail_models = 0,
    forecast_fail_models = 0,
    fit_raw_crossings = 0,
    forecast_raw_crossings = raw_crossings,
    contract_crossings = 0,
    max_forecast_adjustment = if (raw_crossings > 0) 0.02 else 0,
    max_forecast_truth_mae = truth_mae,
    catastrophic_rows = 0,
    fit_reached_max_iter = 0,
    forecast_reached_max_iter = reached_max_iter,
    elapsed_seconds = 24,
    gate_status = if (raw_crossings > 0 || reached_max_iter > 0) "review" else "pass",
    stringsAsFactors = FALSE
  )
}

candidate_bundle <- function(candidate_id, model_id, case_id, scenario_id, shard_dir, truth_mae,
                             raw_crossings = 0L, reached_max_iter = 0L, likelihood = "al",
                             fit_structure = "joint", display_label = "JOINT QDESN RHS",
                             role = "case_candidate") {
  list(
    registry = registry_row(candidate_id, model_id, case_id, scenario_id, role, shard_dir, likelihood, fit_structure),
    health = health_row(candidate_id, raw_crossings, reached_max_iter, truth_mae),
    fit = metric_row(candidate_id, model_id, display_label, likelihood, fit_structure, truth_mae * 0.8, 0, 0, "fit"),
    forecast = metric_row(candidate_id, model_id, display_label, likelihood, fit_structure, truth_mae, raw_crossings, reached_max_iter, "forecast")
  )
}

write_shard <- function(dir, rows) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  registry <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "registry"))
  health <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "health"))
  fit <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "fit"))
  forecast <- app_joint_qdesn_bind_rows(lapply(rows, `[[`, "forecast"))
  nested <- data.frame(
    candidate_id = rep(registry$candidate_id, each = 2L),
    stage = rep(c("fit", "forecast"), times = nrow(registry)),
    label = "artifact_manifest",
    relative_path = "artifact_manifest.csv",
    path = rep(file.path(registry$fit_dir, "artifact_manifest.csv"), each = 2L),
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

tmp_root <- tempfile("joint_qdesn_phase121_")
al_dir <- file.path(tmp_root, "al_high_priority")
exal_dir <- file.path(tmp_root, "exal_high_priority")
p120_dir <- file.path(tmp_root, "phase120_targeted_followup")
out_dir <- file.path(tmp_root, "freeze")

case_a <- "normal_bridge__qdesn_rhs_independent_vb"
case_b <- "regime_shift__joint_qdesn_rhs_vb"
case_c <- "asymmetric_laplace_tail__joint_exqdesn_rhs_vb"

write_shard(al_dir, list(
  candidate_bundle(
    "normal_bridge__qdesn_rhs_independent_vb__selected_controls",
    "qdesn_rhs_independent_vb", case_a, "normal_bridge", al_dir,
    truth_mae = 0.1000, raw_crossings = 0L, reached_max_iter = 0L,
    fit_structure = "independent_single_tau", display_label = "QDESN RHS",
    role = "case_selected_controls_reference"
  ),
  candidate_bundle(
    "regime_shift__joint_qdesn_rhs_vb__selected_controls",
    "joint_qdesn_rhs_vb", case_b, "regime_shift", al_dir,
    truth_mae = 0.1200, raw_crossings = 4L, reached_max_iter = 0L,
    display_label = "JOINT QDESN RHS", role = "case_selected_controls_reference"
  )
))

write_shard(exal_dir, list(
  candidate_bundle(
    "asymmetric_laplace_tail__joint_exqdesn_rhs_vb__selected_controls",
    "joint_exqdesn_rhs_vb", case_c, "asymmetric_laplace_tail", exal_dir,
    truth_mae = 0.1300, raw_crossings = 0L, reached_max_iter = 0L,
    likelihood = "exal", fit_structure = "joint", display_label = "JOINT exQDESN RHS",
    role = "case_selected_controls_reference"
  )
))

write_shard(p120_dir, list(
  candidate_bundle(
    "normal_bridge__qdesn_rhs_independent_vb__phase120_tiny_mae_gain_unstable",
    "qdesn_rhs_independent_vb", case_a, "normal_bridge", p120_dir,
    truth_mae = 0.0997, raw_crossings = 0L, reached_max_iter = 1L,
    fit_structure = "independent_single_tau", display_label = "QDESN RHS"
  ),
  candidate_bundle(
    "regime_shift__joint_qdesn_rhs_vb__phase120_material_gain",
    "joint_qdesn_rhs_vb", case_b, "regime_shift", p120_dir,
    truth_mae = 0.1170, raw_crossings = 0L, reached_max_iter = 0L,
    display_label = "JOINT QDESN RHS"
  )
))

result <- app_joint_qdesn_run_phase121_case_vb_winner_freeze(
  out_dir = out_dir,
  al_high_priority_dir = al_dir,
  exal_high_priority_dir = exal_dir,
  phase120_targeted_dir = p120_dir,
  fixture_dir = tempfile("joint_qdesn_phase121_fixture_"),
  mcmc_out_dir = tempfile("joint_qdesn_phase122_mcmc_"),
  forecast_mae_abs_tolerance = 5.0e-4,
  forecast_mae_rel_tolerance = 0.005,
  n_cores = 2L,
  n_chains = 2L,
  mcmc_n_iter = 12L,
  mcmc_burn = 6L,
  mcmc_thin = 3L
)

check_manifest(result$out_dir)
stopifnot(file.exists(file.path(result$out_dir, "case_winner_selection.csv")))
stopifnot(file.exists(file.path(result$out_dir, "mcmc_readiness_gap_audit.csv")))
stopifnot(nrow(result$candidate_audit) == 5L)
stopifnot(nrow(result$winners) == 3L)
stopifnot(result$run_config$selected_contract_crossings[[1L]] == 0L)
stopifnot(result$run_config$n_fail_winners[[1L]] == 0L)

winner_a <- result$winners[result$winners$case_id == case_a, , drop = FALSE]
stopifnot(nrow(winner_a) == 1L)
stopifnot(winner_a$candidate_id[[1L]] == "normal_bridge__qdesn_rhs_independent_vb__selected_controls")
stopifnot(winner_a$phase121_selection_rule[[1L]] == "within_tolerance_stability_selected")

winner_b <- result$winners[result$winners$case_id == case_b, , drop = FALSE]
stopifnot(nrow(winner_b) == 1L)
stopifnot(winner_b$candidate_id[[1L]] == "regime_shift__joint_qdesn_rhs_vb__phase120_material_gain")
stopifnot(winner_b$phase121_selection_rule[[1L]] == "minimum_forecast_truth_mae_selected")

stopifnot(any(result$mcmc_gap$model_id == "joint_exqdesn_rhs_vb"))
stopifnot(any(result$mcmc_gap$readiness_status == "phase122_runner_required"))
stopifnot(any(result$mcmc_gap$readiness_status == "partial_existing_runner_needs_phase122_case_specific_extension"))
stopifnot(any(grepl("125_run_joint_qdesn_phase122_mcmc_case_confirmation.R", result$launch_plan$command_or_action, fixed = TRUE)))
stopifnot(any(result$gate_audit$gate == "mcmc_scope_readiness" & result$gate_audit$status == "review"))

cat("Joint QDESN Phase 121 case-specific VB winner freeze test passed.\n")
