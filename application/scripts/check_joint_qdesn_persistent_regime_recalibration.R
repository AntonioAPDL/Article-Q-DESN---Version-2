#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pr_default_root()))
root <- normalizePath(args$root, mustWork = TRUE)
print(app_bind_rows_fill(lapply(c("ridge", "rhs", "median_al"), function(stage) app_joint_pr_health(root, stage))))
