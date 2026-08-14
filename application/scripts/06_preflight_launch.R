#!/usr/bin/env Rscript
# Purpose: audit a completed pilot or dry-run directory before any final
# application launch.
# Inputs: a completed run directory identified by --run_id.
# Outputs: launch_readiness_report.csv and launch_readiness_summary.txt.
# Failure behavior: stops if any required readiness check fails.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/launch_readiness.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
if (is.null(args$run_id) || !nzchar(as.character(args$run_id))) {
  stop("06_preflight_launch.R requires --run_id for an existing completed run.", call. = FALSE)
}

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("06_preflight_launch", run_dirs)

report <- app_check_launch_readiness(cfg, run_id = args$run_id)
failed <- app_write_launch_readiness(report, run_dirs)

if (nrow(failed)) {
  msg <- sprintf("%d required launch-readiness checks failed.", nrow(failed))
  app_stage_done("06_preflight_launch", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
}

app_stage_done("06_preflight_launch", run_dirs, message = "Required launch-readiness checks passed; final launch not executed.")
cat(file.path(run_dirs$tables, "launch_readiness_report.csv"), "\n")
