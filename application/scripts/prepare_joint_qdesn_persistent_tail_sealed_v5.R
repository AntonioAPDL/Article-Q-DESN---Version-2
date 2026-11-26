#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_sealed_v5_bootstrap.R"))
args <- commandArgs(TRUE)
if (length(args) < 1L || length(args) > 2L) {
  stop("Usage: prepare V4_SOURCE_ROOT [V5_ROOT]", call. = FALSE)
}
root <- if (length(args) == 2L) args[[2L]] else app_joint_pht5_default_root()
print(app_joint_pht5_prepare(args[[1L]], root)$readiness)
