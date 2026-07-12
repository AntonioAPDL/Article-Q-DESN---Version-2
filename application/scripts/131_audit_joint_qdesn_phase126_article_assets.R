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
  phase126_dir = "application/cache/joint_qdesn_phase126_article_assets_20260712",
  output_dir = "",
  tables_dir = "tables",
  main_tex = "main.tex",
  supplement_tex = "qdesn-supplement.tex"
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

phase126_dir <- resolve_path(arg_value("phase126_dir"), must_work = TRUE)
out_dir <- resolve_path(
  arg_value("output_dir"),
  file.path(phase126_dir, "phase126_readiness_audit"),
  must_work = FALSE
)

result <- app_joint_qdesn_run_phase126_article_asset_audit(
  phase126_dir = phase126_dir,
  tables_dir = resolve_path(arg_value("tables_dir"), must_work = TRUE),
  main_tex = resolve_path(arg_value("main_tex"), must_work = TRUE),
  supplement_tex = resolve_path(arg_value("supplement_tex"), must_work = TRUE),
  out_dir = out_dir
)

cat(sprintf("Joint QDESN Phase 126 article asset audit written to %s\n", result$out_dir))
cat("Audit summary:\n")
print(result$audit_summary, row.names = FALSE)
cat("Asset checks:\n")
print(result$asset_checks[, c("check", "status"), drop = FALSE], row.names = FALSE)
cat("Manuscript checks:\n")
print(result$manuscript_checks[, c("check", "status"), drop = FALSE], row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
