#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_persistent_tail_targeted_bootstrap.R"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Usage: worker.R ROOT STAGE WORKER_ID", call. = FALSE)
root <- args[[1L]]
stage <- args[[2L]]
worker_id <- as.integer(args[[3L]])
if (stage %in% c("m1", "t1")) {
  app_joint_swq_run_worker(root, stage, worker_id)
} else {
  app_joint_pht_run_worker(root, stage, worker_id)
  out <- app_joint_sw_worker_dir(root, stage, worker_id)
  if (file.exists(file.path(out, "FAILED")) || file.exists(file.path(out, "failure.csv"))) {
    stop(sprintf("Targeted %s worker %d failed; inspect %s.", stage, worker_id, out), call. = FALSE)
  }
}
