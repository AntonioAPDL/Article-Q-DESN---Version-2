#!/usr/bin/env Rscript
# Purpose: build the audited forecast-origin application panel.
# Inputs: validated input manifest and schema.
# Outputs: application/cache/application_panel.rds and panel summary tables.
# Failure behavior: stops on schema mismatch, duplicate ensemble rows, or
# inconsistent horizon definitions.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("01_build_panel", run_dirs)

validated <- app_validate_input_manifest(app_config_path(cfg, "input_manifest"), app_config_path(cfg, "schema"), require_files = TRUE)
if (!validated$ok) stop(paste(validated$issues, collapse = "\n"), call. = FALSE)

panel <- app_build_application_panel(cfg, validated$manifest, validated$schema)
app_validate_panel(panel, validated$schema)

cache_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
app_ensure_dir(dirname(cache_path))
saveRDS(panel, cache_path)
summary <- app_panel_summary(panel)
app_write_csv(summary, file.path(run_dirs$tables, "application_panel_summary.csv"))
cov_timeline <- app_panel_covariate_timeline(panel, required = FALSE)
if (!is.null(cov_timeline)) {
  app_write_csv(app_covariate_policy_audit(cov_timeline), file.path(run_dirs$tables, "covariate_policy_audit.csv"))
  app_write_csv(app_covariate_source_manifest(cov_timeline), file.path(run_dirs$tables, "covariate_source_manifest.csv"))
}
app_stage_done("01_build_panel", run_dirs)
cat(cache_path, "\n")
