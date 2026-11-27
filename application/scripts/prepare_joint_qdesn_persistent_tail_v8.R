#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts", "_joint_qdesn_persistent_tail_v8_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) < 1L || length(args) > 2L) stop("Usage: prepare V6_ROOT [V8_ROOT]", call. = FALSE)
root <- if (length(args) == 2L) args[[2L]] else app_joint_pht8_default_root()
print(app_joint_pht8_prepare(args[[1L]], root), row.names = FALSE)
