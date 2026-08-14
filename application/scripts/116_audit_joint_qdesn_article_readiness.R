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
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_article_assets.R"))
source(app_path("application/R/joint_qdesn_article_readiness_audit.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase116_article_readiness_audit_20260709",
  phase113_dir = "application/cache/joint_qdesn_vb_spec_screening_phase113_20260708",
  phase114_freeze_dir = "application/cache/joint_qdesn_phase114_vb_article_candidate_freeze_20260708",
  phase114_mcmc_dir = "application/cache/joint_qdesn_mcmc_article_phase114_20260708",
  phase115_dir = "application/cache/joint_qdesn_article_validation_assets_phase115_20260708"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_repo_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

result <- app_joint_qdesn_run_phase116_article_readiness_audit(
  out_dir = resolve_repo_path(arg_value("output_dir"), must_work = FALSE),
  phase113_dir = resolve_repo_path(arg_value("phase113_dir"), must_work = TRUE),
  phase114_freeze_dir = resolve_repo_path(arg_value("phase114_freeze_dir"), must_work = TRUE),
  phase114_mcmc_dir = resolve_repo_path(arg_value("phase114_mcmc_dir"), must_work = TRUE),
  phase115_dir = resolve_repo_path(arg_value("phase115_dir"), must_work = TRUE)
)

cat(sprintf("Joint QDESN Phase 116 readiness audit written to %s\n", result$out_dir))
cat(sprintf("Artifact manifest: %s\n", result$artifact_manifest_path))
cat("Decision:\n")
print(result$decision, row.names = FALSE)
cat("Health:\n")
print(result$health[, c("component", "status", "immediate_action"), drop = FALSE], row.names = FALSE)
cat("Gate rollup:\n")
print(result$gate_rollup, row.names = FALSE)
