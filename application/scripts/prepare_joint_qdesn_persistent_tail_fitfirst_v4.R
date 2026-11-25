#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_fitfirst_v4_bootstrap.R"))
args <- commandArgs(TRUE)
root <- if (length(args)) args[[1L]] else app_joint_pht4_default_root()
print(app_joint_pht4_prepare(root))
