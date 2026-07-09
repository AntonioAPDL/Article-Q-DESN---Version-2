#!/usr/bin/env Rscript
# Purpose: verify that a copied jerez authoritative source bundle contains the
# source families needed for manuscript-facing GloFAS diagnostics.
# Inputs: copied upstream bundle root, cutoff date, and source requirements.
# Outputs: authoritative_source_bundle_audit.csv and summary text.
# Failure behavior: stops if any required source family or GloFAS version
# evidence is missing.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/authoritative_source_audit.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_application.yaml",
  run_id = NULL,
  bundle_root = "application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505",
  cutoff_date = "2022-12-25",
  requirements = "application/config/authoritative_source_requirements.yaml",
  extra_root = "application/data_local/upstream_jerez/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z"
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("00_audit_authoritative_source_bundle", run_dirs)

result <- tryCatch(
  app_audit_authoritative_source_bundle(
    bundle_root = args$bundle_root,
    cutoff_date = args$cutoff_date,
    requirements_path = app_resolve_path(args$requirements, must_work = TRUE),
    extra_roots = strsplit(args$extra_root %||% "", ",", fixed = TRUE)[[1L]]
  ),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "authoritative_source_bundle_issues.csv"))
    app_stage_done("00_audit_authoritative_source_bundle", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)

failed <- app_write_authoritative_source_audit(result, run_dirs)
if (!result$ok) {
  msg <- paste(sprintf("%s: %s", failed$component, failed$detail), collapse = "; ")
  app_stage_done("00_audit_authoritative_source_bundle", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
}

app_stage_done("00_audit_authoritative_source_bundle", run_dirs)
cat(file.path(run_dirs$tables, "authoritative_source_bundle_audit.csv"), "\n")
