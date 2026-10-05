#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_default_root(), stage = "ridge"))
result <- switch(args$stage,
  ridge = app_joint_pure_finalize_ridge(args$root),
  rhs = app_joint_pure_finalize_rhs(args$root),
  quantile = app_joint_pure_finalize_quantiles(args$root),
  stop("Unknown stage.", call. = FALSE))
print(names(result))
