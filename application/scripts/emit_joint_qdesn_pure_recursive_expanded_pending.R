#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_expanded_default_root(), stage = "ridge"))
ids <- app_joint_pure_expanded_pending_ids(args$root, args$stage)
cat(ids, sep = "\n")
