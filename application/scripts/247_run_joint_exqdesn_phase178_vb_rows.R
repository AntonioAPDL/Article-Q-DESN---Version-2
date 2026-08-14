#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

indices <- strsplit(app_joint_exqdesn_phase176_180_arg("--row-indices", ""), ",", fixed = TRUE)[[1L]]
indices <- as.integer(indices[nzchar(indices)])
if (!length(indices) || any(!is.finite(indices))) stop("--row-indices is required.", call. = FALSE)
result <- app_joint_exqdesn_phase178_run_vb_rows(indices)
print(result, row.names = FALSE)
if (any(result$status == "failed")) quit(status = 1L)
