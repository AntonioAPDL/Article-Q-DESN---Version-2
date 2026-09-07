#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_family_bootstrap.R"))
args <- app_parse_args(list(output_dir = app_joint_shared_family_default_root()))
result <- app_joint_shared_family_prepare(args[["output-dir"]] %||% args$output_dir)
print(result$readiness)
print(result$expected)
cat(sprintf("Prepared seven-family shared-backbone campaign at %s\n", result$root))
