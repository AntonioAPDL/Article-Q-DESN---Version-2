#!/usr/bin/env Rscript
# Purpose: register a frozen local input bundle and write manifest files.
# Inputs: application/config/input_bundle.yaml and expected_schema.yaml.
# Outputs: input_manifest.csv and input_bundle_manifest.csv.
# Failure behavior: stops when required bundle files are missing or hashes cannot
# be computed.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/register_input_bundle.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_application.yaml",
  bundle_config = NULL,
  run_id = NULL,
  require_files = "true"
))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("00_register_input_bundle", run_dirs)

bundle_config <- args$bundle_config %||% app_config_path(cfg, "input_bundle")
bundle_config <- if (grepl("^/", bundle_config)) bundle_config else app_path(bundle_config)
result <- tryCatch(
  app_register_input_bundle(
    bundle_config_path = bundle_config,
    schema_path = app_config_path(cfg, "schema"),
    manifest_output = app_config_path(cfg, "input_manifest"),
    bundle_manifest_output = app_config_path(cfg, "input_bundle_manifest"),
    require_files = app_as_bool(args$require_files)
  ),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "input_bundle_registration_issues.csv"))
    app_stage_done("00_register_input_bundle", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)

app_write_csv(result$bundle_manifest, file.path(run_dirs$manifest, "input_bundle_manifest_registered.csv"))
app_write_csv(result$input_manifest, file.path(run_dirs$manifest, "input_manifest_registered.csv"))

if (!result$ok) {
  app_write_csv(data.frame(issue = result$issues), file.path(run_dirs$logs, "input_bundle_registration_issues.csv"))
  app_stage_done("00_register_input_bundle", run_dirs, status = "failed", message = paste(result$issues, collapse = "; "))
  stop(paste(result$issues, collapse = "\n"), call. = FALSE)
}

app_stage_done("00_register_input_bundle", run_dirs)
cat(app_config_path(cfg, "input_manifest"), "\n")
