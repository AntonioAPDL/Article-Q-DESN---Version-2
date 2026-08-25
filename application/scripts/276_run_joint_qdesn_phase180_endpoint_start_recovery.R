#!/usr/bin/env Rscript

source(file.path(dirname(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L])), "_joint_qdesn_phase180_balanced_score_bootstrap.R"))

recovery_dir <- app_joint_qdesn_phase180_arg("--recovery-dir")
worker_id <- app_joint_qdesn_phase180_arg("--worker-id")
if (is.null(recovery_dir) || is.null(worker_id)) {
  stop("--recovery-dir and --worker-id are required.", call. = FALSE)
}
recovery <- app_joint_qdesn_phase180_load_recovery(recovery_dir)
result <- app_joint_qdesn_phase180_run_worker(
  freeze_dir = recovery$parent$dir,
  worker_id = as.integer(worker_id),
  reuse_completed = !"--no-reuse" %in% commandArgs(trailingOnly = TRUE),
  failure_dir = app_joint_qdesn_phase180_arg("--failure-dir", NULL),
  recovery_dir = recovery$dir
)
cat(sprintf(
  "worker=%d status=%s dir=%s recovery=%s\n",
  result$worker_id, result$status, result$worker_dir,
  recovery$identity$recovery_id[[1L]]
))
