#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v6_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: finalize V6_ROOT STAGE", call. = FALSE)
print(app_joint_pht6_finalize_stage(args[[1L]], args[[2L]]), row.names = FALSE)
