#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_sw_default_root(), stage = "benchmark"))
print(app_joint_sw_finalize_stage(args$root, args$stage))
