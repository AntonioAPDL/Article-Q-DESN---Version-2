#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
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

args <- app_parse_args(list(
  output_dir = "",
  screening_output_dir = "",
  al_high_priority_dir = "",
  exal_high_priority_dir = "",
  fixture_dir = "",
  n_cores = "1"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

phase119_screening_root <- app_joint_qdesn_default_phase119_case_screening_dir()
result <- app_joint_qdesn_run_phase120_case_selection_followup(
  out_dir = resolve_path(
    arg_value("output_dir"),
    app_joint_qdesn_default_phase120_case_followup_dir(),
    must_work = FALSE
  ),
  screening_output_dir = resolve_path(
    arg_value("screening_output_dir"),
    app_joint_qdesn_default_phase120_case_screening_dir(),
    must_work = FALSE
  ),
  al_high_priority_dir = resolve_path(
    arg_value("al_high_priority_dir"),
    file.path(phase119_screening_root, "al_high_priority"),
    must_work = TRUE
  ),
  exal_high_priority_dir = resolve_path(
    arg_value("exal_high_priority_dir"),
    file.path(phase119_screening_root, "exal_high_priority"),
    must_work = TRUE
  ),
  fixture_dir = resolve_path(
    arg_value("fixture_dir"),
    app_joint_qdesn_default_simulation_fixture_dir(),
    must_work = FALSE
  ),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN Phase 120 case-selection follow-up written to %s\n", result$out_dir))
cat("Run decision:\n")
print(result$run_config[, c("readiness_decision", "source_gate_status", "n_case_winners", "n_target_cases", "n_followup_candidate_rows")], row.names = FALSE)
cat("Source health:\n")
print(result$source_health[, c("source_shard", "candidate_rows", "gate_pass", "gate_review", "source_gate")], row.names = FALSE)
cat("Target cases:\n")
print(result$targets[, c("case_id", "followup_status", "forecast_truth_mae", "forecast_raw_crossings", "forecast_reached_max_iter")], row.names = FALSE)
cat("Launch commands:\n")
print(result$launch_commands[, c("command_id", "run_condition")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
