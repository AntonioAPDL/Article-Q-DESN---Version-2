#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_sealed_v5_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: worker V5_ROOT WORKER_ID", call. = FALSE)
app_joint_pht5_run_worker(args[[1L]], as.integer(args[[2L]]))
