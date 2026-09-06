#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_shared_backbone_quantile_bootstrap.R"))
args <- app_parse_args(list(
  output_dir = app_joint_shared_quantile_default_root(),
  parent_dir = app_joint_shared_quantile_default_parent(),
  contract_path = app_joint_shared_quantile_contract_path()
))
result <- app_joint_shared_quantile_prepare(
  out_dir = args[["output-dir"]] %||% args$output_dir,
  parent_dir = args[["parent-dir"]] %||% args$parent_dir,
  contract_path = args[["contract-path"]] %||% args$contract_path
)
print(result$readiness)
cat(sprintf("Prepared shared-backbone quantile continuation at %s\n", result$out_dir))
