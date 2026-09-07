#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))), "_joint_qdesn_shared_backbone_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_default_root(), stage = "ridge"))
health <- if (identical(args$stage, "rhs")) app_joint_shared_rhs_health(args$root) else app_joint_shared_ridge_health(args$root)
print(health)
if (health$failed[[1L]] > 0L) quit(status = 2L)
