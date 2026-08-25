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
source(app_path("application/R/joint_qdesn_article_assets.R"))

args <- app_parse_args(list(
  phase107_dir = "application/cache/joint_qdesn_selected_vb_freeze_phase107_20260707",
  phase109_dir = "application/cache/joint_qdesn_mcmc_article_phase109_20260707",
  tables_dir = "tables",
  figures_dir = "figures/joint_qdesn_simulation",
  output_dir = "application/cache/joint_qdesn_article_validation_assets_phase110_20260707"
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

result <- app_joint_qdesn_run_article_validation_assets(
  phase107_dir = resolve_repo_path(arg_value("phase107_dir"), must_work = TRUE),
  phase109_dir = resolve_repo_path(arg_value("phase109_dir"), must_work = TRUE),
  tables_dir = resolve_repo_path(arg_value("tables_dir"), must_work = TRUE),
  figures_dir = resolve_repo_path(arg_value("figures_dir"), must_work = FALSE),
  out_dir = resolve_repo_path(arg_value("output_dir"), must_work = FALSE)
)

cat(sprintf("Joint QDESN article validation assets written to %s\n", result$out_dir))
cat(sprintf("Tables: %s\n", result$tables_dir))
cat(sprintf("Figures: %s\n", result$figures_dir))
cat(sprintf("Artifact manifest: %s\n", result$artifact_manifest_path))
cat("Readiness:\n")
print(result$readiness, row.names = FALSE)
cat("Gate summary:\n")
print(result$gate_summary, row.names = FALSE)
