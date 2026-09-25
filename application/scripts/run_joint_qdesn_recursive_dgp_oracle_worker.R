#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
args <- app_parse_args(list(
  root = app_joint_recursive_default_root(),
  source_root = app_joint_recursive_default_source(), worker_id = NA_integer_,
  contract_path = app_joint_recursive_contract_path()
))
authorization <- Sys.getenv("JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION")
if (!authorization %in% c(
    "JEREZ_8_PHYSICAL", "JEREZ_PURE_RECURSIVE_15_PHYSICAL")) {
  stop("Oracle worker lacks an approved Jerez physical-core authorization.", call. = FALSE)
}
contract <- app_joint_recursive_read_contract(
  args[["contract-path"]] %||% args$contract_path)
tryCatch({
  path <- app_joint_recursive_run_oracle_shard(
    args$root, args[["source-root"]] %||% args$source_root,
    as.integer(args[["worker-id"]] %||% args$worker_id), contract
  )
  cat(sprintf("Completed recursive oracle worker at %s\n", path))
}, error = function(error) {
  worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
  directory <- app_joint_recursive_oracle_dir(args$root, worker_id)
  app_ensure_dir(directory)
  writeLines(conditionMessage(error), file.path(directory, "FAILED"))
  stop(error)
})
