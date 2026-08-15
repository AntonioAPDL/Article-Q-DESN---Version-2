#!/usr/bin/env Rscript
# Purpose: produce pre-model input diagnostics from the audited panel.
# Inputs: application/cache/application_panel.rds and figure_specs.yaml.
# Outputs: PDF figures and a figure_manifest.csv in the run directory.
# Failure behavior: stops if the panel cache is missing or a figure cannot be
# written.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/figure_provenance.R"))
source(app_path("application/R/plot_input_diagnostics.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("02_make_input_figures", run_dirs)

panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
if (!file.exists(panel_path)) {
  msg <- sprintf("Missing application panel cache: %s. Run 01_build_panel.R first.", panel_path)
  app_stage_done("02_make_input_figures", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
}

panel <- readRDS(panel_path)
validated <- app_validate_input_manifest(app_config_path(cfg, "input_manifest"), app_config_path(cfg, "schema"), require_files = TRUE)
app_validate_panel(panel, validated$schema)

manifest <- tryCatch(
  app_make_input_diagnostic_figures(cfg, panel, run_dirs),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "input_figure_issues.csv"))
    app_stage_done("02_make_input_figures", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)

app_stage_done("02_make_input_figures", run_dirs, message = sprintf("Wrote %d input diagnostic figures.", nrow(manifest)))
cat(file.path(run_dirs$tables, "figure_manifest.csv"), "\n")
