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
  freeze_dir = "",
  phase113_dir = "",
  fixture_dir = "",
  mcmc_output_dir = "",
  article_assets_output_dir = "",
  n_cores = "9",
  n_chains = "2",
  mcmc_n_iter = "1200",
  mcmc_burn = "600",
  mcmc_thin = "10"
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

result <- app_joint_qdesn_run_phase114_vb_article_candidate_freeze(
  freeze_dir = resolve_path(arg_value("freeze_dir"), app_joint_qdesn_default_phase114_vb_freeze_dir(), must_work = FALSE),
  phase113_dir = resolve_path(arg_value("phase113_dir"), app_joint_qdesn_default_phase113_vb_screening_dir(), must_work = TRUE),
  fixture_dir = resolve_path(arg_value("fixture_dir"), app_joint_qdesn_default_simulation_fixture_dir(), must_work = TRUE),
  mcmc_out_dir = resolve_path(arg_value("mcmc_output_dir"), app_joint_qdesn_default_phase114_mcmc_article_dir(), must_work = FALSE),
  article_assets_out_dir = resolve_path(arg_value("article_assets_output_dir"), app_joint_qdesn_default_phase115_article_assets_dir(), must_work = FALSE),
  n_cores = parse_integer(arg_value("n_cores")),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin"))
)

cat(sprintf("Joint QDESN Phase 114 VB article-candidate freeze written to %s\n", result$freeze_dir))
cat("Freeze decision:\n")
print(result$freeze_decision, row.names = FALSE)
cat("Gate audit:\n")
print(result$gate_audit[, c("gate", "status", "detail")], row.names = FALSE)
cat("Launch plan:\n")
print(result$launch_plan[, c("command_id", "command")], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
