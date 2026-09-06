#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))), "_joint_qdesn_shared_backbone_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_shared_default_root()))
result <- app_joint_shared_finalize_ridge(args$root)
cat(sprintf("Finalized %d ridge candidates; %d advance to Gaussian RHS.\n", nrow(result$aggregate), nrow(result$selected)))
