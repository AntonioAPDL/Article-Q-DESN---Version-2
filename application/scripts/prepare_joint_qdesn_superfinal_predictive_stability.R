#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- commandArgs(TRUE)
source_root <- sub("^--source-root=", "", args[grepl("^--source-root=", args)][1L])
root <- sub("^--root=", "", args[grepl("^--root=", args)][1L])
print(app_joint_superfinal_prepare(source_root, root))
