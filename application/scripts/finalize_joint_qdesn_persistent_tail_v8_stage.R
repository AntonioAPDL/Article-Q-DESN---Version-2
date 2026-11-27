#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts", "_joint_qdesn_persistent_tail_v8_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: finalize V8_ROOT STAGE", call. = FALSE)
print(app_joint_pht8_finalize_stage(args[[1L]], args[[2L]]), row.names = FALSE)
