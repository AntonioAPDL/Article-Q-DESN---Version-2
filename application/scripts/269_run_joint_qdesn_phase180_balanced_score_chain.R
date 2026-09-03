#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

freeze_dir <- app_joint_qdesn_phase180_arg("--freeze-dir")
worker_id <- app_joint_qdesn_phase180_arg("--worker-id")
if (is.null(freeze_dir) || is.null(worker_id)) {
  stop("--freeze-dir and --worker-id are required.", call. = FALSE)
}
result <- app_joint_qdesn_phase180_run_worker(
  freeze_dir = freeze_dir, worker_id = as.integer(worker_id),
  reuse_completed = !"--no-reuse" %in% commandArgs(trailingOnly = TRUE),
  failure_dir = app_joint_qdesn_phase180_arg("--failure-dir", NULL)
)
cat(sprintf("worker=%d status=%s dir=%s\n", result$worker_id, result$status,
            result$worker_dir))
