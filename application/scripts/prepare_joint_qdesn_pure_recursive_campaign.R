#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(output_dir = app_joint_pure_default_root()))
result <- app_joint_pure_prepare(args[["output-dir"]] %||% args$output_dir)
print(result$readiness)
