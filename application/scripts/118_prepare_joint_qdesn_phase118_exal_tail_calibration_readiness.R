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
  fixture_dir = "",
  table_dir = "tables",
  tau_summary_path = "",
  phase114_freeze_dir = "",
  phase116_dir = "",
  reference_fit_dir = "",
  reference_forecast_dir = "",
  n_cores = "9"
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

resolve_optional_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) return("")
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

result <- app_joint_qdesn_run_phase118_exal_tail_calibration_readiness(
  out_dir = resolve_path(
    arg_value("output_dir"),
    app_joint_qdesn_default_phase118_exal_tail_readiness_dir(),
    must_work = FALSE
  ),
  screening_output_dir = resolve_path(
    arg_value("screening_output_dir"),
    app_joint_qdesn_default_phase118_vb_screening_dir(),
    must_work = FALSE
  ),
  fixture_dir = resolve_path(
    arg_value("fixture_dir"),
    app_joint_qdesn_default_simulation_fixture_dir(),
    must_work = FALSE
  ),
  table_dir = resolve_path(arg_value("table_dir"), "tables", must_work = TRUE),
  tau_summary_path = resolve_optional_path(arg_value("tau_summary_path"), must_work = TRUE),
  phase114_freeze_dir = resolve_optional_path(arg_value("phase114_freeze_dir"), must_work = FALSE),
  phase116_dir = resolve_optional_path(arg_value("phase116_dir"), must_work = FALSE),
  reference_fit_dir = resolve_optional_path(arg_value("reference_fit_dir"), must_work = FALSE),
  reference_forecast_dir = resolve_optional_path(arg_value("reference_forecast_dir"), must_work = FALSE),
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN Phase 118 exAL tail-calibration readiness written to %s\n", result$out_dir))
cat("Readiness decision:\n")
print(result$run_config[, c("readiness_decision", "article_asset_manifest_status", "n_candidate_rows", "n_high_priority_tail_rows")], row.names = FALSE)
cat("Current model audit:\n")
print(result$model_audit[, c("display_label", "forecast_truth_mae", "forecast_raw_crossings", "article_gate", "phase118_diagnosis")], row.names = FALSE)
cat("Tail-gap priority rows:\n")
print(result$tail_audit[order(-result$tail_audit$joint_exqdesn_minus_joint_qdesn), c("tau", "tail_region", "joint_exqdesn_minus_joint_qdesn", "priority")], row.names = FALSE)
cat("Primary launch command:\n")
cat(result$launch_commands$command[result$launch_commands$command_id == "run_phase118_targeted_vb_screen"][[1L]], "\n")
cat(sprintf("Recommended registry: %s\n", result$paths[["phase118_exal_tail_screening_registry"]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
