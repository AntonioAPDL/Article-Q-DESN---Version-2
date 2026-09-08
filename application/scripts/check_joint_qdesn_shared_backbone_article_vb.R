#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(root = app_joint_article_default_root(), require_complete = FALSE))
check <- app_joint_article_check_vb(
  args$root,
  require_complete = isTRUE(args[["require-complete"]] %||% args$require_complete)
)
print(check$summary)
print(check$by_stage)
if (!identical(check$summary$gate_status[[1L]], "pass")) quit(status = 1L)
