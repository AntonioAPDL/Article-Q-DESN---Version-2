#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_expanded_default_root(), source_root = app_joint_pure_expanded_source_root()))
audit <- app_joint_pure_expanded_import_workers(
  args$root,
  args[["source-root"]] %||% args$source_root,
  "rhs"
)
print(data.frame(imported_rhs_workers = nrow(audit), stringsAsFactors = FALSE))
