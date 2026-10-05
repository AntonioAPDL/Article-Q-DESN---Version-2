#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_expanded_default_root(), source_root = app_joint_pure_expanded_source_root()))
result <- app_joint_pure_expanded_finalize(args$root, args[["source-root"]] %||% args$source_root)
print(result$status)
