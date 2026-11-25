#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_fitfirst_v4_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Usage: worker ROOT STAGE WORKER_ID", call. = FALSE)
app_joint_pht4_run_worker(args[[1L]], args[[2L]], as.integer(args[[3L]]))
