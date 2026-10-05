#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_recursive_default_root(),
  source_root = app_joint_recursive_default_source(),
  contract_path = app_joint_recursive_contract_path()
))
result <- app_joint_recursive_prepare(
  args$root, args[["source-root"]] %||% args$source_root,
  args[["contract-path"]] %||% args$contract_path
)
cat(sprintf(
  "Prepared %d forecast cells and %d primary oracle shards at %s\n",
  nrow(result$cells), sum(app_as_bool_vec(result$oracle$is_primary)), result$root
))
