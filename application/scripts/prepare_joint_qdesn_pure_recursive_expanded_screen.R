#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(
  output_dir = app_joint_pure_expanded_default_root(),
  source_root = app_joint_pure_expanded_source_root(),
  require_pipeline_complete = "true"
))
result <- app_joint_pure_expanded_prepare(
  root = args[["output-dir"]] %||% args$output_dir,
  source_root = args[["source-root"]] %||% args$source_root,
  require_pipeline_complete = app_as_bool(args[["require-pipeline-complete"]] %||% args$require_pipeline_complete)
)
print(result$expected)
print(result$readiness)
