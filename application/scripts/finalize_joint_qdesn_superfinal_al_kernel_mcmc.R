#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- commandArgs(TRUE)
root <- sub("^--root=", "", args[grepl("^--root=", args)][1L])
print(app_joint_alkernel_finalize_mcmc(root))
