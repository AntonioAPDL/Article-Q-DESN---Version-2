#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

worker_id <- as.integer(app_joint_exqdesn_phase176_180_arg("--worker-id"))
freeze_dir <- app_joint_exqdesn_phase176_180_arg("--freeze-dir")
source_id <- app_joint_exqdesn_phase176_180_arg("--source-id")
failure_dir <- app_joint_exqdesn_phase176_180_arg("--failure-dir", "")
if (!is.finite(worker_id) || !nzchar(freeze_dir) || !nzchar(source_id)) {
  stop("--worker-id, --freeze-dir, and --source-id are required.", call. = FALSE)
}
result <- app_joint_exqdesn_phase178_run_m0_worker(
  freeze_dir, worker_id, source_id,
  reuse_completed = TRUE, failure_dir = failure_dir
)
cat(sprintf("%s worker %d: %s\n", source_id, worker_id, result$status))
