#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_stronger_window_bootstrap.R"))
args <- commandArgs(TRUE)
root <- sub("^--root=", "", args[grepl("^--root=", args)][1L])
id <- as.integer(sub("^--worker-id=", "", args[grepl("^--worker-id=", args)][1L]))
app_joint_alkernel_run_mcmc(root, id)
