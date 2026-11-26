#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_sealed_v5_bootstrap.R"))
args <- commandArgs(TRUE)
root <- if (length(args)) args[[1L]] else app_joint_pht5_default_root()
print(app_joint_pht5_check(root), row.names = FALSE)
