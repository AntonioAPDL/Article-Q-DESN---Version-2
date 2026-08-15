repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 124 test.", call. = FALSE)
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
  manifest
}

write_manifested_source <- function(dir, files) {
  app_ensure_dir(dir)
  readme <- file.path(dir, "README.md")
  writeLines(c("# Synthetic source", "", "Used by the Phase 124 regression test."), readme, useBytes = TRUE)
  paths <- c(files, readme = readme)
  invisible(app_joint_qdesn_write_manifest(paths, dir))
}

tmp_root <- tempfile("joint_qdesn_phase124_")
phase123_dir <- file.path(tmp_root, "phase123")
phase119_dir <- file.path(tmp_root, "phase119")
vb_dir <- file.path(tmp_root, "phase124_vb")
out_dir <- file.path(tmp_root, "phase124_prepare")
old_screening_root <- file.path(tmp_root, "joint_qdesn_vb_case_specific_screening_phase119_20260709")

app_ensure_dir(phase123_dir)
scope <- data.frame(
  scenario_id = c("normal_bridge", "normal_bridge", "laplace_bridge", "regime_shift"),
  source_model_id = c(
    "joint_qdesn_rhs_vb",
    "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb",
    "exqdesn_rhs_independent_vb"
  ),
  present_in_phase122 = c(TRUE, FALSE, FALSE, TRUE),
  scenario_label = c("Normal Bridge", "Normal Bridge", "Laplace Bridge", "Regime Shift"),
  model_label = c("Joint QDESN RHS", "Independent QDESN RHS", "Joint exQDESN RHS", "Independent exQDESN RHS"),
  stringsAsFactors = FALSE
)
scope_path <- app_joint_qdesn_phase124_write_csv(scope, file.path(phase123_dir, "article_scope_matrix.csv"))
write_manifested_source(phase123_dir, c(article_scope_matrix = scope_path))

app_ensure_dir(phase119_dir)
make_registry_row <- function(case_id, scenario_id, model_id, suffix) {
  data.frame(
    candidate_id = paste(case_id, suffix, sep = "__"),
    candidate_label = paste(case_id, suffix),
    use_existing_artifacts = FALSE,
    fit_dir = file.path(old_screening_root, "cases", case_id, "candidates", suffix, "fit"),
    forecast_dir = file.path(old_screening_root, "cases", case_id, "candidates", suffix, "forecast"),
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
    candidate_role = "phase124_test_source",
    notes = "synthetic source row",
    scenario_ids = scenario_id,
    model_ids = model_id,
    case_id = case_id,
    case_priority = "test",
    case_focus = "test",
    case_current_forecast_truth_mae = NA_real_,
    case_gap_vs_best_al = NA_real_,
    stringsAsFactors = FALSE
  )
}
missing_case_1 <- "normal_bridge__qdesn_rhs_independent_vb"
missing_case_2 <- "laplace_bridge__joint_exqdesn_rhs_vb"
registry <- do.call(rbind, list(
  make_registry_row(missing_case_1, "normal_bridge", "qdesn_rhs_independent_vb", "selected_controls"),
  make_registry_row(missing_case_1, "normal_bridge", "qdesn_rhs_independent_vb", "tau0_0p5_zeta2_16"),
  make_registry_row(missing_case_2, "laplace_bridge", "joint_exqdesn_rhs_vb", "selected_controls"),
  make_registry_row(missing_case_2, "laplace_bridge", "joint_exqdesn_rhs_vb", "inner14_iter2400")
))
registry_path <- app_joint_qdesn_phase124_write_csv(registry, file.path(phase119_dir, "phase119_case_specific_screening_registry.csv"))
write_manifested_source(phase119_dir, c(phase119_case_specific_screening_registry = registry_path))

result <- app_joint_qdesn_run_phase124_balanced_completion_prepare(
  out_dir = out_dir,
  phase123_dir = phase123_dir,
  phase119_readiness_dir = phase119_dir,
  vb_completion_dir = vb_dir,
  fixture_dir = tmp_root,
  workers = 3L,
  n_cores_per_worker = 1L,
  run_id = "phase124_test",
  session_prefix = "joint_qdesn_phase124_test"
)

stopifnot(nrow(result$missing_cells) == 2L)
stopifnot(nrow(result$registry) == 4L)
stopifnot(setequal(result$missing_cells$case_id, c(missing_case_1, missing_case_2)))
stopifnot(all(grepl(normalizePath(vb_dir, winslash = "/", mustWork = FALSE), result$registry$fit_dir, fixed = TRUE)))
stopifnot(all(grepl(normalizePath(vb_dir, winslash = "/", mustWork = FALSE), result$registry$forecast_dir, fixed = TRUE)))
stopifnot(!any(grepl("joint_qdesn_vb_case_specific_screening_phase119_20260709", result$registry$fit_dir, fixed = TRUE)))
stopifnot(all(result$source_map$phase124_source_candidate_id == result$source_map$candidate_id))
stopifnot(all(result$gates$status %in% c("pass", "review")))
stopifnot(result$run_config$readiness_decision[[1L]] == "ready_to_launch_phase124_vb_balanced_completion")
stopifnot(any(grepl("123_launch_joint_qdesn_screening_parallel_chunks.sh", result$launch_plan$command, fixed = TRUE)))
stopifnot(any(grepl("--audit-only true", result$launch_plan$command, fixed = TRUE)))
invisible(check_manifest(result$out_dir))

cat("joint_qdesn_phase124_balanced_completion tests passed\n")
