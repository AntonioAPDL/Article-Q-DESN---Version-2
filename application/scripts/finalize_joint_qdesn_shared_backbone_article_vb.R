#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(root = app_joint_article_default_root()))
result <- app_joint_article_finalize_vb(args$root)
print(result$summary)
cat("Finalized 32 compact JOINT article VB initializers.\n")
