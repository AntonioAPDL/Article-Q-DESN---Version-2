#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_default_root()))
rows <- list(app_joint_pure_health(args$root, "ridge"), app_joint_pure_health(args$root, "rhs"),
  cbind(stage = "quantile_vb", app_joint_pure_quantile_health(args$root)))
print(app_bind_rows_fill(rows))
