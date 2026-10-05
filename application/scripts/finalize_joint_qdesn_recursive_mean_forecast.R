#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
args <- app_parse_args(list(
  root = app_joint_recursive_default_root(),
  contract_path = app_joint_recursive_contract_path(),
  review_contract_path = app_joint_recursive_review_contract_path()
))
contract <- app_joint_recursive_read_contract(
  args[["contract-path"]] %||% args$contract_path)
review_contract_path <- args[["review-contract-path"]] %||%
  args$review_contract_path
result <- app_joint_recursive_finalize(args$root, contract,
  allowed_review_contract_sha256 = app_sha256_file(review_contract_path))
print(result$health, row.names = FALSE)
cat(sprintf("Final recursive score packet: %s\n", file.path(args$root, "final_packet")))
