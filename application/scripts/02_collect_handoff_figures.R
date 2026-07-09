#!/usr/bin/env Rscript
# Purpose: collect audited GEFS/NWM handoff figures into the article run tree.
# Inputs: copied GEFS/NWM handoff run and selected cutoff date.
# Outputs: local run copies of precipitation and soil-moisture figures plus a
# provenance manifest with hashes.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  config = "application/config/glofas_dec25_authoritative_source_figures.yaml",
  run_id = NULL,
  cutoff_date = "2022-12-25",
  handoff_run_root = "application/data_local/upstream_jerez/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z"
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("02_collect_handoff_figures", run_dirs)

cutoff_date <- as.Date(args$cutoff_date)
if (is.na(cutoff_date)) stop("cutoff_date must be a valid date.", call. = FALSE)
handoff_run_root <- app_resolve_path(args$handoff_run_root, must_work = TRUE)
source_dir <- file.path(handoff_run_root, "plots", sprintf("cutoff_date=%s", cutoff_date))
if (!dir.exists(source_dir)) {
  msg <- sprintf("Missing handoff plot directory: %s", source_dir)
  app_stage_done("02_collect_handoff_figures", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
}

targets <- c(
  "soil_forecasts_mean_same_units_bias_matched_with_covariates.pdf",
  "soil_forecasts_mean_same_units_bias_matched_with_covariates.png",
  "precip_forecasts_mean_same_units_quantiles_with_covariates.pdf",
  "precip_forecasts_mean_same_units_quantiles_with_covariates.png",
  "plot_summary_mean_same_units_bias_quantiles_with_covariates.json"
)

out_dir <- file.path(run_dirs$figures, "handoff_diagnostics", sprintf("cutoff_date=%s", cutoff_date))
app_ensure_dir(out_dir)
rows <- lapply(targets, function(name) {
  src <- file.path(source_dir, name)
  if (!file.exists(src)) stop(sprintf("Missing required handoff figure artifact: %s", src), call. = FALSE)
  dest <- file.path(out_dir, name)
  file.copy(src, dest, overwrite = TRUE)
  data.frame(
    artifact_id = tools::file_path_sans_ext(name),
    cutoff_date = as.character(cutoff_date),
    source_path = app_prefer_repo_relative_path(src),
    output_path = app_prefer_repo_relative_path(dest),
    sha256 = app_sha256_file(dest),
    size_bytes = file.info(dest)$size,
    source_handoff_root = app_prefer_repo_relative_path(handoff_run_root),
    run_id = basename(run_dirs$run_dir),
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
})
manifest <- do.call(rbind, rows)
app_write_csv(manifest, file.path(run_dirs$tables, "handoff_figure_manifest.csv"))

app_stage_done(
  "02_collect_handoff_figures",
  run_dirs,
  message = sprintf("Collected %d GEFS/NWM handoff figure artifacts.", nrow(manifest))
)
cat(file.path(run_dirs$tables, "handoff_figure_manifest.csv"), "\n")
