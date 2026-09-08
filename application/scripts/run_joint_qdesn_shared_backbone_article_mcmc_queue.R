#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_article_default_root(),
  max_workers = 40L
))

result <- app_joint_article_run_mcmc_queue(
  root = args$root,
  max_workers = as.integer(args[["max-workers"]] %||% args$max_workers)
)
print(result$summary)
print(result$final$assessment)
cat("JOINT article MCMC queue completed and final confirmation manifest verified.\n")
