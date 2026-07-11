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
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase124_balanced_completion.R"))

args <- app_parse_args(list(
  output_dir = "",
  phase123_dir = "",
  phase119_readiness_dir = "",
  vb_completion_dir = "",
  fixture_dir = "",
  workers = "12",
  n_cores_per_worker = "1",
  run_id = "phase124_20260711",
  session_prefix = "joint_qdesn_phase124_vb_20260711"
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
  normalizePath(out, winslash = "/", mustWork = must_work)
}

result <- app_joint_qdesn_run_phase124_balanced_completion_prepare(
  out_dir = resolve_path(
    arg_value("output_dir"),
    app_joint_qdesn_default_phase124_balanced_completion_dir(),
    must_work = FALSE
  ),
  phase123_dir = resolve_path(
    arg_value("phase123_dir"),
    app_joint_qdesn_default_phase123_mcmc_article_freeze_dir(),
    must_work = TRUE
  ),
  phase119_readiness_dir = resolve_path(
    arg_value("phase119_readiness_dir"),
    app_joint_qdesn_default_phase119_case_readiness_dir(),
    must_work = TRUE
  ),
  vb_completion_dir = resolve_path(
    arg_value("vb_completion_dir"),
    app_joint_qdesn_default_phase124_vb_completion_dir(),
    must_work = FALSE
  ),
  fixture_dir = resolve_path(
    arg_value("fixture_dir"),
    app_joint_qdesn_default_simulation_fixture_dir(),
    must_work = FALSE
  ),
  workers = parse_integer(arg_value("workers")),
  n_cores_per_worker = parse_integer(arg_value("n_cores_per_worker")),
  run_id = as.character(arg_value("run_id"))[[1L]],
  session_prefix = as.character(arg_value("session_prefix"))[[1L]]
)

cat(sprintf("Joint QDESN Phase 124 balanced-completion preparation written to %s\n", result$out_dir))
cat("Health summary:\n")
print(result$health[, c("component", "status", "progress"), drop = FALSE], row.names = FALSE)
cat("Gate summary:\n")
print(result$gates[, c("gate", "status"), drop = FALSE], row.names = FALSE)
cat("Missing cells by model:\n")
print(as.data.frame(table(result$missing_cells$source_model_id), stringsAsFactors = FALSE), row.names = FALSE)
cat("Launch command:\n")
print(result$launch_plan[result$launch_plan$command_id == "launch_phase124_vb_completion", "command"], quote = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
