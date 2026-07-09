#!/usr/bin/env Rscript
# Purpose: execute the full GloFAS application workflow for one run ID.
# Failure behavior: stops at the first failed stage.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/launch_control.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_application.yaml",
  run_id = NULL,
  preflight = FALSE,
  confirm_final_launch = FALSE,
  allow_existing_run_dir = FALSE
))
cfg <- app_read_config(app_path(args$config))
run_id <- args$run_id %||% app_run_id(cfg)

stage_files <- c(
  "00_check_inputs.R",
  "00_audit_input_bundle.R",
  "01_build_panel.R",
  "02_make_input_figures.R",
  "03_fit_models.R",
  "04_score_models.R",
  "05_make_outputs.R"
)
if (isTRUE(cfg$post_analysis$run_after_outputs %||% FALSE)) {
  stage_files <- c(stage_files, "07_post_analysis.R")
}
if (app_as_bool(args$preflight)) {
  stage_files <- c(stage_files, "06_preflight_launch.R")
}

stage_plan <- app_validate_run_all_launch_request(
  cfg,
  run_id = run_id,
  stage_files = stage_files,
  confirm_final_launch = args$confirm_final_launch,
  allow_existing_run_dir = args$allow_existing_run_dir,
  preflight = args$preflight
)
run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
app_write_csv(stage_plan, file.path(run_dirs$manifest, "run_all_stage_plan.csv"))

for (stage in stage_files) {
  cmd <- file.path("application", "scripts", stage)
  stage_args <- c("--config", args$config, "--run_id", run_id)
  if (identical(stage, "03_fit_models.R") && app_as_bool(args$confirm_final_launch)) {
    stage_args <- c(stage_args, "--confirm_final_launch", "true")
  }
  old <- setwd(app_repo_root())
  status <- system2("Rscript", c(cmd, stage_args))
  setwd(old)
  if (!identical(status, 0L)) {
    stop(sprintf("Application stage failed: %s", stage), call. = FALSE)
  }
}

cat(file.path(app_config_path(cfg, "runs"), run_id), "\n")
