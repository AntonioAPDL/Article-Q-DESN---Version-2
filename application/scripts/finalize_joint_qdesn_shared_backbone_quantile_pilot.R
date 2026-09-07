#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_quantile_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_quantile_default_root()))
result <- app_joint_shared_quantile_finalize(args$root)
print(result$health)
print(result$contrasts, row.names = FALSE)
print(result$decision, row.names = FALSE)
