#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase182_dense_grid_crossing_bootstrap.R"
))

freeze_dir <- app_joint_qdesn_phase182_arg("--freeze-dir")
worker_id <- as.integer(app_joint_qdesn_phase182_arg("--worker-id"))
failure_dir <- app_joint_qdesn_phase182_arg("--failure-dir", NULL)
if (is.null(freeze_dir) || !is.finite(worker_id)) {
  stop("Usage: --freeze-dir <path> --worker-id <integer>", call. = FALSE)
}
result <- app_joint_qdesn_phase182_run_worker(
  freeze_dir = freeze_dir, worker_id = worker_id,
  failure_dir = failure_dir
)
cat(sprintf(
  "worker_id=%d status=%s worker_dir=%s\n",
  result$worker_id, result$status, result$worker_dir
))
