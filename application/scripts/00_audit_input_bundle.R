#!/usr/bin/env Rscript
# Purpose: audit registered input files before panel construction.
# Inputs: input_manifest.csv, expected_schema.yaml, and local frozen inputs.
# Outputs: input_bundle_audit.csv and input_profile.csv in the run tables.
# Failure behavior: stops if a required semantic check fails.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/audit_input_bundle.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("00_audit_input_bundle", run_dirs)

result <- tryCatch(
  app_audit_input_bundle(cfg, run_dirs = run_dirs),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "input_bundle_audit_issues.csv"))
    app_stage_done("00_audit_input_bundle", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)

if (!result$ok) {
  issues <- result$audit[result$audit$status != "ok", , drop = FALSE]
  app_write_csv(issues, file.path(run_dirs$logs, "input_bundle_audit_issues.csv"))
  app_stage_done("00_audit_input_bundle", run_dirs, status = "failed", message = paste(issues$detail, collapse = "; "))
  stop(paste(issues$detail, collapse = "\n"), call. = FALSE)
}

app_stage_done("00_audit_input_bundle", run_dirs)
cat(file.path(run_dirs$tables, "input_bundle_audit.csv"), "\n")
