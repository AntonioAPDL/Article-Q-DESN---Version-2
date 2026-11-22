#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_sw_default_root()))
stages <- c("benchmark", "r1a", "r1b", "r2", "r3", "h1", "h2", "h3")
print(app_bind_rows_fill(lapply(stages, function(stage) app_joint_sw_health(args$root, stage))))
