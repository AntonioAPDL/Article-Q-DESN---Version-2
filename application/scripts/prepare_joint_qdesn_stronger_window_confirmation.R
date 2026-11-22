#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- commandArgs(TRUE); root <- sub("^--root=", "", args[grepl("^--root=", args)][1L])
if (is.na(root) || !nzchar(root)) root <- app_joint_sw_default_root()
print(app_joint_swcf_prepare_sentinel(root))
