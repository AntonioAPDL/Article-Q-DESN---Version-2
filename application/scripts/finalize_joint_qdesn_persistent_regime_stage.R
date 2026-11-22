#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pr_default_root(), stage = "ridge"))
result <- switch(args$stage,
  ridge = app_joint_pr_finalize_ridge(args$root),
  rhs = app_joint_pr_finalize_rhs(args$root),
  median_al = app_joint_pr_finalize_median_al(args$root),
  stop("Unknown targeted recalibration stage.", call. = FALSE))
print(names(result))
