#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_persistent_tail_exploration_v3_bootstrap.R"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Usage: worker.R ROOT STAGE WORKER_ID", call. = FALSE)
app_joint_pht3_run_worker(args[[1L]], args[[2L]], as.integer(args[[3L]]))
