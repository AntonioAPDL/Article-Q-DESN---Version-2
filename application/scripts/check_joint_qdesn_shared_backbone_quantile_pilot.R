#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_quantile_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_quantile_default_root()))
health <- app_joint_shared_quantile_health(args$root)
by_stage <- app_joint_shared_quantile_health_by_stage(args$root)
print(health)
print(by_stage, row.names = FALSE)
if (health$failed[[1L]] > 0L) quit(status = 2L)
