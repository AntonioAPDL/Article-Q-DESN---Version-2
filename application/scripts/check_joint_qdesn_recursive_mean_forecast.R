#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
args <- app_parse_args(list(
  root = app_joint_recursive_default_root(),
  source_root = app_joint_recursive_default_source(),
  contract_path = app_joint_recursive_contract_path(), aggregate_oracles = FALSE,
  require_sentinels = FALSE, require_complete = FALSE
))
contract <- app_joint_recursive_read_contract(
  args[["contract-path"]] %||% args$contract_path)
flag <- function(value) app_as_bool_vec(value)[[1L]]
if (flag(args[["aggregate-oracles"]] %||% args$aggregate_oracles)) {
  result <- app_joint_recursive_aggregate_oracles(
    args$root, args[["source-root"]] %||% args$source_root, contract)
  cat(sprintf("Oracle aggregation status: %s\n", result$status))
  if (identical(result$status, "extension_required")) quit(status = 20L)
}
oracle <- app_joint_recursive_oracle_status(args$root)
cells <- app_joint_recursive_cell_status(args$root)
oracle_health <- as.data.frame(table(oracle$status), stringsAsFactors = FALSE)
cell_health <- as.data.frame(table(cells$inference_method, cells$status), stringsAsFactors = FALSE)
print(oracle_health, row.names = FALSE)
print(cell_health, row.names = FALSE)
app_write_csv(oracle, file.path(args$root, "oracle_worker_health.csv"))
app_write_csv(cells, file.path(args$root, "forecast_worker_health.csv"))
if (flag(args[["require-sentinels"]] %||% args$require_sentinels)) {
  sentinels <- cells[app_as_bool_vec(cells$sentinel), , drop = FALSE]
  if (nrow(sentinels) != 3L || any(sentinels$status != "complete")) {
    stop("Recursive sentinel gate is incomplete.", call. = FALSE)
  }
}
if (flag(args[["require-complete"]] %||% args$require_complete) &&
    (nrow(cells) != 64L || any(cells$status != "complete"))) {
  stop("Recursive production cells are incomplete.", call. = FALSE)
}
