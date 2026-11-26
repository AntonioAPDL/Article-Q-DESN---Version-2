#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd())
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v6_bootstrap.R"))
args <- commandArgs(TRUE)
root <- if (length(args)) args[[1L]] else app_joint_pht6_default_root()
check <- app_joint_pht6_check(root)
print(check, row.names = FALSE)
if (check$status != "PASS") quit(status = 1L)
