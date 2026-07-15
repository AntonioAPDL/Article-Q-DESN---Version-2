repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase133 test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

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

script <- file.path(repo_root, "application/scripts/138_audit_joint_exqdesn_performance_first_phase133.R")
stopifnot(file.exists(script))

out_dir <- tempfile("joint_exqdesn_phase133_")
status <- system2(file.path(R.home("bin"), "Rscript"), c(script, "--output-dir", out_dir))
stopifnot(identical(status, 0L))

expected_files <- c(
  "run_config.csv",
  "source_manifest_audit.csv",
  "joint_exqdesn_model_performance_context.csv",
  "joint_exqdesn_performance_gap_audit.csv",
  "joint_exqdesn_sampler_vs_qhat_stability_audit.csv",
  "joint_exqdesn_latest_sampler_state.csv",
  "joint_exqdesn_scenario_priority_table.csv",
  "joint_exqdesn_stage_decision_matrix.csv",
  "posterior_summary_sensitivity_readiness.csv",
  "phase132_replacement_readiness.csv",
  "joint_exqdesn_next_experiment_plan.csv",
  "audit_assessment.csv",
  "provenance.csv",
  "README.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(out_dir, expected_files))))
check_manifest(out_dir)

source_manifest <- utils::read.csv(file.path(out_dir, "source_manifest_audit.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(source_manifest) == 6L)
stopifnot(all(source_manifest$status == "pass"))
stopifnot(all(source_manifest$n_hash_fail == 0L))

assessment <- utils::read.csv(file.path(out_dir, "audit_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(identical(assessment$implementation_gate[[1L]], "pass"))
stopifnot(identical(assessment$audit_gate[[1L]], "review"))
stopifnot(as.integer(assessment$n_large_performance_gaps[[1L]]) >= 1L)
stopifnot(grepl("qhat_summary", assessment$next_stage_recommendation[[1L]]))

priority <- utils::read.csv(file.path(out_dir, "joint_exqdesn_scenario_priority_table.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(priority) == 8L)
required_priority_cols <- c(
  "scenario_id", "forecast_mae_gap_to_best", "performance_priority",
  "sampler_priority", "primary_diagnosis", "recommended_next_action"
)
stopifnot(all(required_priority_cols %in% names(priority)))
stopifnot(priority$scenario_id[[1L]] == "regime_shift")
stopifnot("nonlinear_reservoir_friendly" %in% priority$scenario_id)
nonlinear <- priority[priority$scenario_id == "nonlinear_reservoir_friendly", , drop = FALSE]
stopifnot(identical(nonlinear$sampler_priority[[1L]], "high"))
stopifnot(grepl("sampler", nonlinear$recommended_next_action[[1L]]))

posterior <- utils::read.csv(file.path(out_dir, "posterior_summary_sensitivity_readiness.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(posterior) == 4L)
stopifnot(all(posterior$readiness %in% c(
  "requires_scored_or_draw_level_rerun",
  "possible_from_existing_artifact"
)))

phase132 <- utils::read.csv(file.path(out_dir, "phase132_replacement_readiness.csv"), stringsAsFactors = FALSE)
stopifnot(identical(phase132$replacement_status[[1L]], "not_promotable_from_phase132_alone"))
stopifnot(!isTRUE(phase132$phase132_has_full_score_tables[[1L]]))

plan <- utils::read.csv(file.path(out_dir, "joint_exqdesn_next_experiment_plan.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(plan) == 6L)
stopifnot(identical(plan$phase_label[[1L]], "Phase133A"))
stopifnot(any(plan$phase_label == "Phase133B"))

cat("joint_exqdesn_phase133_performance_first_audit tests passed\n")
