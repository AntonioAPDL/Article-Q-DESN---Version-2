#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pr2_default_root()))
root <- normalizePath(args$root, mustWork = TRUE)
stages <- c("parity", "ridge", "seed_ridge", "rhs", "rhs_refine", "median_al", "tail_al")
print(app_bind_rows_fill(lapply(stages, function(stage) app_joint_pr2_health(root, stage))))
