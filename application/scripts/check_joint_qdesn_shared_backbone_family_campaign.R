#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_family_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_family_default_root()))
health <- app_joint_shared_family_health(args$root)
print(health, row.names = FALSE)
cat(sprintf("Completed %d/%d jobs; failures=%d; remaining=%d\n",
  sum(health$completed), sum(health$expected), sum(health$failed), sum(health$remaining)))
