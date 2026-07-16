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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase135_matched_spec_readiness.R"))

args <- app_parse_args(list(
  output_dir = "",
  screening_output_dir = "",
  phase134_dir = "",
  phase121_dir = "",
  phase124c_dir = "",
  phase125_dir = "",
  fixture_dir = "",
  workers = "8",
  n_cores_per_worker = "1"
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

result <- app_joint_exqdesn_run_phase135_matched_spec_readiness(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_exqdesn_phase135_default_dir(), must_work = FALSE),
  screening_output_dir = resolve_path(arg_value("screening_output_dir"), app_joint_exqdesn_phase135_default_screening_dir(), must_work = FALSE),
  phase134_dir = resolve_path(arg_value("phase134_dir"), app_joint_exqdesn_phase135_default_phase134_dir(), must_work = TRUE),
  phase121_dir = resolve_path(arg_value("phase121_dir"), app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(), must_work = TRUE),
  phase124c_dir = resolve_path(arg_value("phase124c_dir"), app_joint_exqdesn_phase135_default_phase124c_dir(), must_work = TRUE),
  phase125_dir = resolve_path(arg_value("phase125_dir"), app_joint_exqdesn_phase135_default_phase125_dir(), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE),
  workers = parse_integer(arg_value("workers")),
  n_cores_per_worker = parse_integer(arg_value("n_cores_per_worker"))
)

cat(sprintf("Joint exQDESN Phase135 matched-spec readiness written to %s\n", result$out_dir))
cat("Assessment:\n")
print(result$assessment, row.names = FALSE)
cat("Phase134 per-scenario winner decisions:\n")
print(result$phase134_winners[, c(
  "scenario_ids", "candidate_id", "phase134_forecast_mae_improvement",
  "phase135_decision_class", "phase135_next_action"
)], row.names = FALSE)
cat("Matched-spec parity summary:\n")
print(result$parity_audit[, c(
  "scenario_id", "pair_id", "current_tau0_same",
  "current_all_compared_controls_same", "source_al_tau0", "current_exal_tau0"
)], row.names = FALSE)
cat("Launch command:\n")
print(result$launch_commands$command[result$launch_commands$command_id == "launch_phase135_matched_exal_screen"])
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
