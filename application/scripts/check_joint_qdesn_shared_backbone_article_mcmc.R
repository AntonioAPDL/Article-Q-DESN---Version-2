#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(root = app_joint_article_default_root()))
check <- app_joint_article_check_mcmc(args$root)
print(check$summary)
if (!identical(check$summary$gate_status[[1L]], "pass")) quit(status = 1L)
