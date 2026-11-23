#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pr2_default_root(), stage = "parity"))
result <- switch(args$stage,
  parity = app_joint_pr2_finalize_parity(args$root),
  ridge = app_joint_pr2_finalize_ridge(args$root),
  seed_ridge = app_joint_pr2_finalize_seed(args$root),
  rhs = app_joint_pr2_finalize_rhs(args$root),
  rhs_refine = app_joint_pr2_finalize_rhs_refine(args$root),
  median_al = app_joint_pr2_finalize_median(args$root),
  tail_al = app_joint_pr2_finalize_tail(args$root),
  stop("Unknown targeted v2 finalization stage.", call. = FALSE))
print(if (is.list(result)) names(result) else result)
