repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 119 readiness test.", call. = FALSE)
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
    stopifnot(identical(as.numeric(file.info(path)$size), as.numeric(manifest$size_bytes[[ii]])))
  }
  invisible(manifest)
}

tmp_root <- tempfile("joint_qdesn_phase119_article_")
table_dir <- file.path(tmp_root, "tables")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

model_summary <- data.frame(
  model_id = c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb", "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"),
  display_label = c("JOINT QDESN RHS", "QDESN RHS", "JOINT exQDESN RHS", "exQDESN RHS"),
  likelihood = c("al", "al", "exal", "exal"),
  fit_structure = c("joint", "independent_single_tau", "joint", "independent_single_tau"),
  fit_truth_mae = c(0.08, 0.09, 0.12, 0.13),
  fit_truth_rmse = c(0.10, 0.11, 0.16, 0.17),
  fit_check_loss = c(0.15, 0.15, 0.16, 0.16),
  fit_raw_crossings = c(0, 2, 0, 0),
  fit_contract_crossings = c(0, 0, 0, 0),
  fit_max_iter_rows = c(0, 1, 0, 1),
  fit_gate_status = c("pass", "pass;review", "pass", "pass;review"),
  forecast_truth_mae = c(0.09, 0.10, 0.16, 0.14),
  forecast_truth_rmse = c(0.12, 0.13, 0.20, 0.18),
  forecast_check_loss = c(0.16, 0.16, 0.17, 0.17),
  crps_grid_mean = c(0.36, 0.36, 0.38, 0.37),
  abs_hit_rate_error = c(0.02, 0.02, 0.04, 0.035),
  abs_coverage_error = c(0.03, 0.03, 0.08, 0.07),
  forecast_raw_crossings = c(1, 20, 0, 0),
  forecast_contract_crossings = c(0, 0, 0, 0),
  forecast_max_iter_rows = c(0, 1, 0, 1),
  forecast_max_adjustment = c(0.01, 0.08, 0, 0),
  forecast_gate_status = c("pass;review", "pass;review", "pass", "pass;review"),
  model_label = c("Joint QDESN RHS", "Independent QDESN RHS", "Joint exQDESN RHS", "Independent exQDESN RHS"),
  model_role = c("primary", "comparator", "comparator", "comparator"),
  article_gate = c("review", "review", "pass", "review"),
  stringsAsFactors = FALSE
)

scenario_summary <- data.frame(
  Scenario = c("Nonlinear Reservoir Friendly", "Student-t Location-Scale", "Heteroskedastic Seasonal"),
  `Joint QDESN` = c("0.102 (0.144)", "0.068 (0.089)", "0.088 (0.118)"),
  `Independent QDESN` = c("0.121 (0.159)", "0.073 (0.101)", "0.093 (0.128)"),
  `Joint exQDESN` = c("0.200 (0.249)", "0.134 (0.165)", "0.093 (0.122)"),
  `Independent exQDESN` = c("0.198 (0.248)", "0.130 (0.161)", "0.086 (0.114)"),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

model_path <- file.path(table_dir, "joint_qdesn_article_validation_vb_model_summary.csv")
scenario_path <- file.path(table_dir, "joint_qdesn_article_validation_vb_scenario_summary.csv")
utils::write.csv(model_summary, model_path, row.names = FALSE)
utils::write.csv(scenario_summary, scenario_path, row.names = FALSE)

asset_manifest <- data.frame(
  label = c("vb_model_summary", "vb_scenario_summary"),
  artifact_type = c("table", "table"),
  path = c("tables/joint_qdesn_article_validation_vb_model_summary.csv", "tables/joint_qdesn_article_validation_vb_scenario_summary.csv"),
  size_bytes = as.numeric(file.info(c(model_path, scenario_path))$size),
  sha256 = vapply(c(model_path, scenario_path), app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
utils::write.csv(asset_manifest, file.path(table_dir, "joint_qdesn_article_validation_asset_manifest.csv"), row.names = FALSE)

out_dir <- tempfile("joint_qdesn_phase119_")
screen_dir <- tempfile("joint_qdesn_phase119_screen_")
fixture_dir <- tempfile("joint_qdesn_phase119_fixture_")

result <- app_joint_qdesn_run_phase119_case_specific_calibration_readiness(
  out_dir = out_dir,
  screening_output_dir = screen_dir,
  fixture_dir = fixture_dir,
  table_dir = table_dir,
  n_cores = 1L
)

check_manifest(result$out_dir)

stopifnot(identical(result$run_config$article_asset_manifest_status[[1L]], "pass"))
stopifnot(identical(result$run_config$readiness_decision[[1L]], "ready_to_prepare_case_specific_screening"))
stopifnot(nrow(result$case_table) == 12L)
stopifnot(all(c("case_id", "scenario_id", "model_id", "priority", "case_focus") %in% names(result$case_table)))
stopifnot(any(result$case_table$priority == "high"))
stopifnot(nrow(result$registry) > nrow(result$case_table))
stopifnot(!anyDuplicated(result$registry$candidate_id))
stopifnot(all(nzchar(result$registry$scenario_ids)))
stopifnot(all(nzchar(result$registry$model_ids)))
stopifnot(all(vapply(result$registry$scenario_ids, function(x) length(app_joint_qdesn_parse_id_csv(x)) == 1L, logical(1L))))
stopifnot(all(vapply(result$registry$model_ids, function(x) length(app_joint_qdesn_parse_id_csv(x)) == 1L, logical(1L))))
app_joint_qdesn_validate_screening_registry(result$registry, allow_alpha_prior_vectors = FALSE)

stopifnot(all(file.exists(unname(result$shard_paths))))
stopifnot(any(result$launch_commands$command_id == "run_phase119_exal_high_priority"))
stopifnot(any(grepl("121_launch_joint_qdesn_phase119_parallel_chunks.sh", result$launch_commands$command, fixed = TRUE)))
stopifnot(any(grepl("--workers", result$launch_commands$command, fixed = TRUE)))
stopifnot(any(grepl("--fixture-dir", result$launch_commands$command, fixed = TRUE)))

selection <- utils::read.csv(file.path(result$out_dir, "selection_policy.csv"), stringsAsFactors = FALSE)
stopifnot(all(c("gate_name", "gate_type", "rule", "rationale") %in% names(selection)))
stopifnot(any(selection$gate_name == "case_scope"))
stopifnot(any(selection$gate_name == "fresh_holdout_confirmation"))

cat("Joint QDESN Phase 119 case-specific calibration readiness test passed.\n")
