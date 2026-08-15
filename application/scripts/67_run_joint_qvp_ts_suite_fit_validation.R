#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
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
source(app_path("application/R/joint_qvp_qdesn.R"))

out_dir <- if (length(args) >= 1L && nzchar(args[[1L]])) {
  args[[1L]]
} else {
  app_path("application/cache/joint_qvp_ts_suite_fit_validation_20260701")
}

result <- app_joint_qvp_run_ts_suite_fit_validation(out_dir = out_dir)
gate_counts <- table(result$suite_assessment$gate_status)
cat(sprintf("Joint-QVP time-series suite fit-validation artifacts written to %s\n", result$out_dir))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
cat("Gate counts:\n")
print(gate_counts)
