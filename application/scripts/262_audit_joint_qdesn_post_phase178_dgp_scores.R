#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1"
)
cache_root <- app_joint_exqdesn_phase176_180_arg(
  "--cache-root", app_path("application/cache")
)
result <- app_joint_qdesn_postscore_run_audit(
  cache_root = cache_root,
  contract_dir = app_joint_exqdesn_phase176_180_arg("--contract-dir", NULL),
  out_dir = app_joint_exqdesn_phase176_180_arg("--output-dir", NULL),
  work_dir = app_joint_exqdesn_phase176_180_arg("--work-dir", NULL),
  cores = as.integer(app_joint_exqdesn_phase176_180_arg("--cores", "8")),
  force = "--force" %in% commandArgs(trailingOnly = TRUE)
)
cat(sprintf(
  "Post-Phase178 DGP-integrated score audit: %s\nGate: %s\n",
  result$out_dir, result$assessment$gate_status[[1L]]
))
