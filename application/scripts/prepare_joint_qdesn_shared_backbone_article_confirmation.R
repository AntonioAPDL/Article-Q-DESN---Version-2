#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

args <- app_parse_args(list(
  output_dir = app_joint_article_default_root(),
  source_root = app_joint_article_default_source_runtime(),
  force = FALSE
))

result <- app_joint_article_prepare(
  out_dir = args[["output-dir"]] %||% args$output_dir,
  source_root = args[["source-root"]] %||% args$source_root,
  force = isTRUE(args$force) || "--force" %in% commandArgs(trailingOnly = TRUE),
  dry_run = TRUE
)

print(result$readiness)
cat(sprintf("Prepared launch-free JOINT article confirmation preflight at %s\n", result$out_dir))
