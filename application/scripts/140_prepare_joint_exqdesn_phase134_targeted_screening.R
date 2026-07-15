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
source(app_path("application/R/joint_exqdesn_phase134_targeted_screening.R"))

args <- app_parse_args(list(
  output_dir = "",
  screening_output_dir = "",
  phase133b_dir = "",
  phase121_dir = "",
  fixture_dir = "",
  workers = "10",
  n_cores_per_worker = "1"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out) || out <= 0L) stop(sprintf("Expected positive integer value, got '%s'.", x), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

result <- app_joint_exqdesn_run_phase134_targeted_screening_readiness(
  out_dir = resolve_path(arg_value("output_dir"), app_joint_exqdesn_phase134_default_dir(), must_work = FALSE),
  screening_output_dir = resolve_path(arg_value("screening_output_dir"), app_joint_exqdesn_phase134_default_screening_dir(), must_work = FALSE),
  phase133b_dir = resolve_path(arg_value("phase133b_dir"), app_joint_exqdesn_phase134_default_phase133b_dir(), must_work = TRUE),
  phase121_dir = resolve_path(arg_value("phase121_dir"), app_joint_qdesn_default_phase121_case_vb_freeze_dir_fallback(), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE),
  workers = parse_integer(arg_value("workers")),
  n_cores_per_worker = parse_integer(arg_value("n_cores_per_worker"))
)

cat(sprintf("Joint exQDESN Phase134 targeted-screening readiness written to %s\n", result$out_dir))
cat("Assessment:\n")
print(result$assessment, row.names = FALSE)
cat("Candidate design by case:\n")
print(result$design_summary$by_case, row.names = FALSE)
cat("Candidate design by role:\n")
print(result$design_summary$by_role, row.names = FALSE)
cat("Launch command:\n")
print(result$launch_commands$command[result$launch_commands$command_id == "launch_phase134_targeted_screen"][[1L]])
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
