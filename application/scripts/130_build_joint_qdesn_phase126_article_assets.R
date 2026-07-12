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
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase125_balanced_mcmc_audit.R"))
source(app_path("application/R/joint_qdesn_phase126_article_assets.R"))

args <- app_parse_args(list(
  phase125_dir = "application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712",
  output_dir = "application/cache/joint_qdesn_phase126_article_assets_20260712",
  tables_dir = "tables"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, default = "", must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

result <- app_joint_qdesn_run_phase126_article_assets(
  phase125_dir = resolve_path(arg_value("phase125_dir"), must_work = TRUE),
  tables_dir = resolve_path(arg_value("tables_dir"), must_work = TRUE),
  out_dir = resolve_path(arg_value("output_dir"), must_work = FALSE)
)

cat(sprintf("Joint QDESN Phase 126 article assets written to %s\n", result$out_dir))
cat(sprintf("Tables written to %s\n", result$tables_dir))
cat("Readiness:\n")
print(result$readiness, row.names = FALSE)
cat("Model table:\n")
print(result$model_table, row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$artifact_manifest_path))
