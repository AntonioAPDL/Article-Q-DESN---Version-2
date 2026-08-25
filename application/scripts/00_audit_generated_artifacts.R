#!/usr/bin/env Rscript
# Purpose: report generated or heavy local artifacts without deleting them.
# Outputs: a CSV inventory under the run directory or local audit directory.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_application.yaml",
  run_id = NULL,
  output = "",
  inventory_level = "file",
  large_file_mb = "50"
))

cfg <- app_read_config(app_path(args$config))
large_file_mb <- suppressWarnings(as.numeric(args$large_file_mb))
if (!is.finite(large_file_mb) || large_file_mb <= 0) large_file_mb <- 50
inventory_level <- tolower(as.character(args$inventory_level %||% "file"))

if (inventory_level %in% c("run", "runs", "run_level")) {
  inventory <- app_run_level_artifact_inventory(root = app_repo_root())
} else if (inventory_level %in% c("file", "files", "file_level")) {
  inventory <- app_generated_artifact_inventory(
    root = app_repo_root(),
    large_file_bytes = large_file_mb * 1024^2
  )
} else {
  stop("Unknown --inventory_level. Use 'file' or 'run'.", call. = FALSE)
}

if (nzchar(as.character(args$output %||% ""))) {
  out_path <- if (grepl("^/", args$output)) args$output else app_path(args$output)
} else if (!is.null(args$run_id) && nzchar(as.character(args$run_id))) {
  run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
  out_name <- if (inventory_level %in% c("run", "runs", "run_level")) {
    "generated_run_artifact_inventory.csv"
  } else {
    "generated_artifact_inventory.csv"
  }
  out_path <- file.path(run_dirs$tables, out_name)
} else {
  out_prefix <- if (inventory_level %in% c("run", "runs", "run_level")) {
    "generated_run_artifact_inventory"
  } else {
    "generated_artifact_inventory"
  }
  out_path <- app_path(
    "application/runs/local_audits",
    sprintf("%s_%s.csv", out_prefix, format(Sys.time(), "%Y%m%d_%H%M%S"))
  )
}

app_write_csv(inventory, out_path)
cat(out_path, "\n")
