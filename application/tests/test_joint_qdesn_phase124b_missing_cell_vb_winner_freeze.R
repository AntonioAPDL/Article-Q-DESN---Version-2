repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 124b test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase124_balanced_completion.R"))

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

tmp_root <- tempfile("joint_qdesn_phase124b_")
prepare_dir <- file.path(tmp_root, "phase124_prepare")
vb_dir <- file.path(tmp_root, "phase124_vb")
out_dir <- file.path(tmp_root, "phase124b")
fixture_dir <- file.path(tmp_root, "fixtures")
app_ensure_dir(prepare_dir)
app_ensure_dir(vb_dir)
app_ensure_dir(fixture_dir)

missing_cells <- data.frame(
  scenario_id = c("normal_bridge", "laplace_bridge"),
  source_model_id = c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb"),
  case_id = c("normal_bridge__joint_qdesn_rhs_vb", "laplace_bridge__qdesn_rhs_independent_vb"),
  stringsAsFactors = FALSE
)
missing_path <- app_joint_qdesn_phase124_write_csv(missing_cells, file.path(prepare_dir, "phase124_missing_cells.csv"))
prep_readme <- file.path(prepare_dir, "README.md")
writeLines("# Phase124 prepare test", prep_readme, useBytes = TRUE)
invisible(app_joint_qdesn_write_manifest(c(phase124_missing_cells = missing_path, readme = prep_readme), prepare_dir))

make_candidate <- function(case_id, scenario_id, model_id, suffix, truth_mae, raw_cross = 0L, reached_max = 0L) {
  candidate_id <- paste(case_id, suffix, sep = "__")
  data.frame(
    candidate_id = candidate_id,
    candidate_label = paste(case_id, suffix),
    use_existing_artifacts = FALSE,
    fit_dir = file.path(tmp_root, "candidate_artifacts", case_id, suffix, "fit"),
    forecast_dir = file.path(tmp_root, "candidate_artifacts", case_id, suffix, "forecast"),
    vb_max_iter = 240L,
    adaptive_vb_max_iter_grid = "240,480",
    vb_tol = 1.0e-4,
    rhs_vb_inner = 5L,
    tau0 = 1,
    zeta2 = 16,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd = "1",
    alpha_min_spacing = 0,
    gamma_init_policy = "zero",
    review_adjustment_threshold = 1.0e-3,
    max_dense_dim = 300L,
    n_cores = 1L,
    candidate_role = "phase124b_test_candidate",
    notes = "synthetic test candidate",
    scenario_ids = scenario_id,
    model_ids = model_id,
    case_id = case_id,
    case_priority = "phase124b_test",
    case_focus = "test",
    case_current_forecast_truth_mae = NA_real_,
    case_gap_vs_best_al = NA_real_,
    truth_mae = truth_mae,
    raw_cross = raw_cross,
    reached_max = reached_max,
    stringsAsFactors = FALSE
  )
}

reg_extra <- do.call(rbind, list(
  make_candidate("normal_bridge__joint_qdesn_rhs_vb", "normal_bridge", "joint_qdesn_rhs_vb", "accurate_review", 0.1000, raw_cross = 1L),
  make_candidate("normal_bridge__joint_qdesn_rhs_vb", "normal_bridge", "joint_qdesn_rhs_vb", "stable_within_tol", 0.1002, raw_cross = 0L),
  make_candidate("laplace_bridge__qdesn_rhs_independent_vb", "laplace_bridge", "qdesn_rhs_independent_vb", "best", 0.0900, raw_cross = 0L)
))
registry <- reg_extra[, setdiff(names(reg_extra), c("truth_mae", "raw_cross", "reached_max")), drop = FALSE]
app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)

health <- data.frame(
  candidate_id = reg_extra$candidate_id,
  candidate_label = reg_extra$candidate_label,
  manifest_status = "pass",
  fit_models = 1L,
  forecast_models = 1L,
  scenario_worker_failures = 0L,
  fit_worker_failures = 0L,
  forecast_worker_failures = 0L,
  fit_fail_models = 0L,
  forecast_fail_models = 0L,
  fit_raw_crossings = 0L,
  forecast_raw_crossings = reg_extra$raw_cross,
  contract_crossings = 0L,
  max_forecast_adjustment = ifelse(reg_extra$raw_cross > 0, 0.02, 0),
  max_forecast_truth_mae = reg_extra$truth_mae,
  catastrophic_rows = 0L,
  fit_reached_max_iter = 0L,
  forecast_reached_max_iter = reg_extra$reached_max,
  elapsed_seconds = c(10, 11, 12),
  gate_status = ifelse(reg_extra$raw_cross > 0 | reg_extra$reached_max > 0, "review", "pass"),
  stringsAsFactors = FALSE
)

metric_template <- function(stage) {
  data.frame(
    candidate_id = reg_extra$candidate_id,
    candidate_label = reg_extra$candidate_label,
    candidate_role = reg_extra$candidate_role,
    tau0 = registry$tau0,
    zeta2 = registry$zeta2,
    alpha_prior_sd = registry$alpha_prior_sd,
    alpha_min_spacing = registry$alpha_min_spacing,
    gamma_init_policy = registry$gamma_init_policy,
    scenario_ids = registry$scenario_ids,
    model_ids = registry$model_ids,
    vb_max_iter = registry$vb_max_iter,
    adaptive_vb_max_iter_grid = registry$adaptive_vb_max_iter_grid,
    rhs_vb_inner = registry$rhs_vb_inner,
    stage = stage,
    model_id = registry$model_ids,
    display_label = ifelse(registry$model_ids == "joint_qdesn_rhs_vb", "JOINT QDESN RHS", "QDESN RHS"),
    likelihood = "al",
    fit_structure = ifelse(registry$model_ids == "joint_qdesn_rhs_vb", "joint", "independent_single_tau"),
    truth_mae = if (stage == "fit") reg_extra$truth_mae * 0.9 else reg_extra$truth_mae,
    truth_sq_error = reg_extra$truth_mae^2,
    truth_rmse = reg_extra$truth_mae * 1.2,
    check_loss_mean = reg_extra$truth_mae * 1.5,
    crps_grid_mean = reg_extra$truth_mae * 3,
    abs_hit_rate_error = 0.01,
    abs_coverage_error = 0.02,
    interval_width_mean = 1,
    interval_score_mean = 2,
    raw_crossing_pairs = if (stage == "forecast") reg_extra$raw_cross else 0L,
    contract_crossing_pairs = 0L,
    reached_max_iter = if (stage == "forecast") reg_extra$reached_max else 0L,
    elapsed_seconds = 5,
    max_abs_adjustment = ifelse(reg_extra$raw_cross > 0, 0.02, 0),
    adjustment_rate = ifelse(reg_extra$raw_cross > 0, 0.01, 0),
    finite_quantiles = TRUE,
    finite_scores = TRUE,
    gate_status = ifelse(reg_extra$raw_cross > 0 | reg_extra$reached_max > 0, "review", "pass"),
    stringsAsFactors = FALSE
  )
}

candidate_manifest <- data.frame(
  candidate_id = reg_extra$candidate_id,
  stage = "fit",
  label = "dummy",
  relative_path = "dummy.csv",
  path = "dummy.csv",
  exists = TRUE,
  declared_sha256 = paste(rep("a", 64), collapse = ""),
  actual_sha256 = paste(rep("a", 64), collapse = ""),
  declared_size_bytes = 1,
  actual_size_bytes = 1,
  status = "pass",
  stringsAsFactors = FALSE
)

paths <- c(
  candidate_registry = app_joint_qdesn_phase124_write_csv(registry, file.path(vb_dir, "candidate_registry.csv")),
  screening_health_summary = app_joint_qdesn_phase124_write_csv(health, file.path(vb_dir, "screening_health_summary.csv")),
  fit_model_metric_summary = app_joint_qdesn_phase124_write_csv(metric_template("fit"), file.path(vb_dir, "fit_model_metric_summary.csv")),
  forecast_model_metric_summary = app_joint_qdesn_phase124_write_csv(metric_template("forecast"), file.path(vb_dir, "forecast_model_metric_summary.csv")),
  candidate_manifest_verification = app_joint_qdesn_phase124_write_csv(candidate_manifest, file.path(vb_dir, "candidate_manifest_verification.csv"))
)
vb_readme <- file.path(vb_dir, "README.md")
writeLines("# Phase124 VB test", vb_readme, useBytes = TRUE)
invisible(app_joint_qdesn_write_manifest(c(paths, readme = vb_readme), vb_dir))

result <- app_joint_qdesn_run_phase124b_missing_cell_vb_winner_freeze(
  out_dir = out_dir,
  phase124_prepare_dir = prepare_dir,
  phase124_vb_dir = vb_dir,
  fixture_dir = fixture_dir,
  mcmc_out_dir = file.path(tmp_root, "phase124c"),
  n_cores = 2L,
  n_chains = 1L,
  mcmc_n_iter = 20L,
  mcmc_burn = 10L,
  mcmc_thin = 2L
)

stopifnot(nrow(result$winners) == 2L)
stopifnot(all(result$coverage$coverage_status == "pass"))
stopifnot(file.exists(file.path(result$out_dir, "case_winner_controls.csv")))
stopifnot(file.exists(file.path(result$out_dir, "case_winner_metric_summary.csv")))
stopifnot(file.exists(file.path(result$out_dir, "case_winner_gate_audit.csv")))
stopifnot(any(grepl("125_run_joint_qdesn_phase122_mcmc_case_confirmation.R", result$launch_plan$command, fixed = TRUE)))
stopifnot(any(result$controls$phase121_selection_status %in% c("pass", "review")))
check_manifest(result$out_dir)

cat("joint_qdesn_phase124b_missing_cell_vb_winner_freeze tests passed\n")
