#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_fitfirst_v4_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: finalizer ROOT STAGE", call. = FALSE)
print(app_joint_pht4_finalize_stage(args[[1L]], args[[2L]]))
