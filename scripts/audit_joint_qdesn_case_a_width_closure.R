#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5L) {
  stop(paste(
    "Usage: audit_joint_qdesn_case_a_width_closure.R",
    "REPO_ROOT FRESH_CONFIRMATION_CSV ARCHITECTURE_COMPARISON_CSV",
    "MEAN_DESIGN_DIAGNOSTICS_CSV OUTPUT_DIR"
  ), call. = FALSE)
}

repo_root <- normalizePath(args[[1L]], mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/joint_qdesn_case_a_width_closure.R"))

result <- app_joint_case_a_width_run_audit(
  repo_root = repo_root,
  confirmation_path = args[[2L]],
  comparison_path = args[[3L]],
  mean_design_path = args[[4L]],
  output_dir = args[[5L]]
)

cat(sprintf(
  "Case A audit complete: %s\nDecision: %s\n",
  result$output_dir, result$decision$decision[[1L]]
))
