#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_confirmation_root(), workers = 15L))
Sys.setenv(JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION = "VB",
  JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED = "JEREZ_PURE_RECURSIVE_15_PHYSICAL")
app_joint_article_run_vb_queue(args$root, as.integer(args$workers))
app_joint_article_finalize_vb(args$root)
