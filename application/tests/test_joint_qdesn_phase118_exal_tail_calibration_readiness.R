repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase 118 readiness test.", call. = FALSE)
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

tau_summary <- tempfile("phase118_tau_", fileext = ".csv")
utils::write.csv(
  data.frame(
    tau = c(0.05, 0.50, 0.95),
    tail_region = c("lower_tail", "center", "upper_tail"),
    joint_qdesn_truth_mae = c(0.12, 0.06, 0.14),
    joint_exqdesn_truth_mae = c(0.19, 0.061, 0.31),
    qdesn_independent_truth_mae = c(0.16, 0.04, 0.15),
    exqdesn_independent_truth_mae = c(0.19, 0.04, 0.29),
    joint_exqdesn_minus_joint_qdesn = c(0.07, 0.001, 0.17),
    exqdesn_independent_minus_qdesn_independent = c(0.03, 0.00, 0.14),
    stringsAsFactors = FALSE
  ),
  tau_summary,
  row.names = FALSE
)

out_dir <- tempfile("joint_qdesn_phase118_")
screen_dir <- tempfile("joint_qdesn_phase118_screen_")
fixture_dir <- tempfile("joint_qdesn_phase118_fixture_")

result <- app_joint_qdesn_run_phase118_exal_tail_calibration_readiness(
  out_dir = out_dir,
  screening_output_dir = screen_dir,
  fixture_dir = fixture_dir,
  tau_summary_path = tau_summary,
  n_cores = 1L
)

check_manifest(result$out_dir)

stopifnot(identical(result$run_config$article_asset_manifest_status[[1L]], "pass"))
stopifnot(identical(result$run_config$readiness_decision[[1L]], "ready_to_launch_targeted_vb_screen_after_review"))
stopifnot(nrow(result$model_audit) == 4L)
stopifnot(all(c("joint_qdesn_rhs_vb", "joint_exqdesn_rhs_vb", "qdesn_rhs_independent_vb", "exqdesn_rhs_independent_vb") %in% result$model_audit$model_id))
stopifnot(nrow(result$scenario_audit) >= 9L)
stopifnot(any(result$tail_audit$priority == "high"))
stopifnot(identical(result$tail_audit$source_tau_summary_sha256[[1L]], app_sha256_file(tau_summary)))
stopifnot(nrow(result$registry) >= 8L)
stopifnot(!anyDuplicated(result$registry$candidate_id))
stopifnot(any(result$registry$candidate_id == "phase113_selected_controls_rerun"))
stopifnot(all(result$registry$use_existing_artifacts == FALSE))
app_joint_qdesn_validate_screening_registry(result$registry, allow_alpha_prior_vectors = FALSE)
stopifnot(all(c("selection_policy.csv", "launch_commands.csv", "phase118_exal_tail_screening_registry.csv") %in% basename(unname(result$paths))))
stopifnot(any(grepl("106_run_joint_qdesn_vb_spec_screening.R", result$launch_commands$command, fixed = TRUE)))
stopifnot(any(grepl("98_generate_joint_qdesn_simulation_dgp_fixtures.R", result$launch_commands$command, fixed = TRUE)))

source_manifest <- utils::read.csv(file.path(result$out_dir, "source_asset_manifest_verification.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(source_manifest) == 23L)
stopifnot(all(source_manifest$status == "pass"))

selection <- utils::read.csv(file.path(result$out_dir, "selection_policy.csv"), stringsAsFactors = FALSE)
stopifnot(all(c("gate_name", "gate_type", "pass_or_review_rule", "rationale") %in% names(selection)))
stopifnot(any(selection$gate_name == "fresh_holdout_confirmation"))

cat("Joint QDESN Phase 118 exAL tail-calibration readiness test passed.\n")
