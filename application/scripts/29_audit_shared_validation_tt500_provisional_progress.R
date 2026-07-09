#!/usr/bin/env Rscript

script_file <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/validation_interface_contract.R"))

args <- app_parse_args(list(
  config = app_default_tt500_provisional_progress_config(),
  require_hashes = TRUE
))

result <- app_validate_tt500_provisional_progress(
  config_path = args$config,
  require_hashes = app_as_bool(args$require_hashes)
)

atomic <- result$atomic
root <- result$root
cat("TT500 provisional progress audit: PASS\n")
cat(sprintf("config: %s\n", normalizePath(args$config, winslash = "/", mustWork = TRUE)))
cat(sprintf("run_tag: %s\n", result$config$run_tag))
cat(sprintf("atomic_rows: %d\n", nrow(atomic)))
cat(sprintf("root_rows: %d\n", nrow(root)))
cat(sprintf("atomic_complete: %d\n", sum(atomic$completion_state == "complete", na.rm = TRUE)))
cat(sprintf("atomic_running: %d\n", sum(atomic$completion_state == "running", na.rm = TRUE)))
cat(sprintf("atomic_pending: %d\n", sum(atomic$completion_state == "pending", na.rm = TRUE)))
cat("article_consumable: FALSE\n")
cat("is_final: FALSE\n")
