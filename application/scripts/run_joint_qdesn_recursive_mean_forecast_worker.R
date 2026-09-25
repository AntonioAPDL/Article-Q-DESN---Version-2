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
  stop("Forecast worker lacks an approved Jerez physical-core authorization.", call. = FALSE)
}
contract <- app_joint_recursive_read_contract(
  args[["contract-path"]] %||% args$contract_path)
tryCatch({
  path <- app_joint_recursive_run_cell(
    args$root, args[["source-root"]] %||% args$source_root,
    as.integer(args[["worker-id"]] %||% args$worker_id), contract
  )
  cat(sprintf("Completed recursive forecast worker at %s\n", path))
}, error = function(error) {
  worker_id <- as.integer(args[["worker-id"]] %||% args$worker_id)
  directory <- app_joint_recursive_cell_dir(args$root, worker_id)
  app_ensure_dir(directory)
  failure_path <- file.path(directory, "failure_diagnostics.csv")
  if (!file.exists(failure_path)) {
    progress_path <- file.path(directory, "stability_progress.csv")
    diagnostics <- if (file.exists(progress_path)) {
      progress <- app_read_csv(progress_path)
      progress[, setdiff(names(progress), c(
        "contract_version", "contract_sha256", "failure_message"
      )), drop = FALSE]
    } else {
      data.frame(
        tier_index = NA_integer_, tier = NA_character_,
        half_split_method = contract$state_half_split_method,
        stringsAsFactors = FALSE
      )
    }
    app_joint_recursive_write_failure_diagnostics(
      directory, diagnostics, contract, conditionMessage(error)
    )
  }
  writeLines(conditionMessage(error), file.path(directory, "FAILED"))
  stop(error)
})
