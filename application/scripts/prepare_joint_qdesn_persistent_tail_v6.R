#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v6_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) < 2L || length(args) > 3L) {
  stop("Usage: prepare V4_SOURCE_ROOT V5_SOURCE_ROOT [V6_ROOT]", call. = FALSE)
}
root <- if (length(args) == 3L) args[[3L]] else app_joint_pht6_default_root()
print(app_joint_pht6_prepare(args[[1L]], args[[2L]], root)$readiness, row.names = FALSE)
