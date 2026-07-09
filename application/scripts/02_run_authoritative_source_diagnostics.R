#!/usr/bin/env Rscript
# Purpose: run the audited source-diagnostic workflow over all copied
# authoritative jerez cutoffs.
# Inputs: copied jerez cutoff directories and GEFS/NWM handoff cache.
# Outputs: one run directory per cutoff plus a combined source-diagnostic
# summary table. Generated data and runs remain ignored by git.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/authoritative_source_audit.R"))
source(app_path("application/R/authoritative_cutoff_materialization.R"))

args <- app_parse_args(list(
  bundle_root = "application/data_local/upstream_jerez/frozen_shared_inputs/exalm_t1_authoritative_20260505",
  extra_root = "application/data_local/upstream_jerez/gefs_nwm_forecast_runs/gefs_nwm_forecast_manifest_source_native_tranche1_20260406T194500Z",
  requirements = "application/config/authoritative_source_requirements.yaml",
  output_bundle_root = "application/data_local/frozen_inputs/authoritative_cutoffs",
  generated_config_root = "application/cache/authoritative_source_configs",
  run_id = "authoritative_source_cutoffs_20260512",
  cutoff_dates = "",
  station_id = "11160500",
  collect_handoff = "true",
  stop_on_failure = "true"
))

bundle_root <- app_resolve_path(args$bundle_root, must_work = TRUE)
extra_roots <- strsplit(args$extra_root %||% "", ",", fixed = TRUE)[[1L]]
requirements_path <- app_resolve_path(args$requirements, must_work = TRUE)
output_bundle_root <- app_resolve_path(args$output_bundle_root, must_work = FALSE)
generated_config_root <- app_resolve_path(file.path(args$generated_config_root, args$run_id), must_work = FALSE)
summary_run_dir <- app_path("application/runs", args$run_id)
summary_tables_dir <- file.path(summary_run_dir, "tables")
summary_logs_dir <- file.path(summary_run_dir, "logs")
app_ensure_dir(summary_tables_dir)
app_ensure_dir(summary_logs_dir)

discover_cutoffs <- function(root) {
  dirs <- list.dirs(root, recursive = FALSE, full.names = FALSE)
  vals <- sub("^cutoff_date=", "", dirs[grepl("^cutoff_date=", dirs)])
  vals <- vals[!is.na(as.Date(vals))]
  sort(vals)
}

cutoff_dates <- if (nzchar(args$cutoff_dates)) {
  trimws(strsplit(args$cutoff_dates, ",", fixed = TRUE)[[1L]])
} else {
  discover_cutoffs(bundle_root)
}
if (!length(cutoff_dates)) stop("No cutoff dates were found.", call. = FALSE)

write_cutoff_config_files <- function(cutoff_date, bundle_dir, cfg_dir) {
  cutoff_id <- sprintf("cutoff_%s", gsub("-", "", cutoff_date))
  app_ensure_dir(cfg_dir)

  input_bundle <- list(
    version = 0.1,
    bundle_id = sprintf("authoritative_glofas_%s", gsub("-", "", cutoff_date)),
    description = sprintf("Audited jerez source diagnostic bundle for cutoff %s.", cutoff_date),
    bundle_root = app_prefer_repo_relative_path(bundle_dir),
    copy_files = FALSE,
    manifest_output = "application/manifests/input_manifest.csv",
    bundle_manifest_output = "application/manifests/input_bundle_manifest.csv",
    inputs = list(
      reference_gauge = list(
        source_name = "reference gauge streamflow",
        source_type = "observation",
        relative_path = "reference/reference_gauge.csv",
        upstream_reference = sprintf("jerez frozen shared input cutoff_date=%s inputs/usgs_daily.csv", cutoff_date),
        date_columns = "date",
        required = TRUE,
        notes = "USGS daily streamflow at site 11160500 in cubic meters per second."
      ),
      glofas_retrospective = list(
        source_name = "GloFAS retrospective streamflow",
        source_type = "retrospective_forecast",
        relative_path = "glofas/glofas_retrospective.csv",
        upstream_reference = sprintf("jerez frozen shared input cutoff_date=%s forecats_bundle/inputs/retros_daily.csv", cutoff_date),
        date_columns = "date",
        required = TRUE,
        notes = "Audited GloFAS historical retrospective series for the cutoff."
      ),
      glofas_ensemble = list(
        source_name = "GloFAS ensemble streamflow forecasts",
        source_type = "ensemble_forecast",
        relative_path = "glofas/glofas_ensemble.csv",
        upstream_reference = sprintf("jerez frozen shared input cutoff_date=%s forecats_bundle/inputs/glofas_members.csv", cutoff_date),
        date_columns = c("origin_date", "target_date"),
        required = TRUE,
        notes = "Issued GloFAS member forecasts reshaped from wide to long format."
      ),
      ppt_soil_covariates = list(
        source_name = "precipitation and soil covariates",
        source_type = "covariate",
        relative_path = "covariates/ppt_soil_covariates.csv",
        upstream_reference = sprintf("jerez frozen shared input cutoff_date=%s covariates/cov_03_PPT.csv, cov_04_SOIL.csv", cutoff_date),
        date_columns = "date",
        required = FALSE,
        notes = "Model-facing realized precipitation and soil-moisture covariates; GDPC/PCA/climate-index columns are excluded from the readout."
      ),
      climate_covariates = list(
        source_name = "diagnostic climate covariates",
        source_type = "covariate",
        relative_path = "covariates/climate_covariates.csv",
        upstream_reference = sprintf("jerez frozen shared input cutoff_date=%s covariates/cov_03_PPT.csv, cov_04_SOIL.csv, cov_05_PCA.csv", cutoff_date),
        date_columns = "date",
        required = FALSE,
        notes = "Diagnostic/provenance covariates copied for source checks; not used by the active model readout."
      )
    )
  )
  input_bundle_path <- file.path(cfg_dir, "input_bundle.yaml")
  app_write_yaml(input_bundle, input_bundle_path)

  cutoffs <- data.frame(
    cutoff_id = cutoff_id,
    origin_date = cutoff_date,
    train_start = "1979-02-01",
    train_end = cutoff_date,
    eval_start = as.character(as.Date(cutoff_date) + 1L),
    eval_end = as.character(as.Date(cutoff_date) + 30L),
    horizon_min = 1L,
    horizon_max = 30L,
    split = "diagnostic",
    enabled = TRUE,
    notes = sprintf("Audited jerez source diagnostic for GloFAS origin %s.", cutoff_date),
    stringsAsFactors = FALSE
  )
  cutoffs_path <- file.path(cfg_dir, "cutoffs.csv")
  app_write_csv(cutoffs, cutoffs_path)

  figure_specs <- list(
    version = 0.1,
    description = sprintf("Cutoff-centered source diagnostic figures for audited GloFAS cutoff %s.", cutoff_date),
    graphics = list(device = "pdf", width = 7.0, height = 4.5),
    figures = list(
      input_coverage_timeline = list(enabled = TRUE, filename = "input_coverage_timeline.pdf", title = "Input record coverage"),
      reference_glofas_retrospective_series = list(enabled = TRUE, filename = "reference_glofas_retrospective_series.pdf", title = "Reference and GloFAS retrospective series"),
      glofas_ensemble_fan_selected_origins = list(enabled = TRUE, filename = "glofas_ensemble_fan_selected_origins.pdf", title = "GloFAS ensemble fan for selected origins", max_origins = 1L),
      horizon_member_availability_heatmap = list(enabled = TRUE, filename = "horizon_member_availability_heatmap.pdf", title = "Ensemble member availability by origin and horizon"),
      reference_glofas_retrospective_scatter = list(enabled = TRUE, filename = "reference_glofas_retrospective_scatter.pdf", title = "Reference versus GloFAS retrospective"),
      retrospective_discrepancy_by_month = list(enabled = TRUE, filename = "retrospective_discrepancy_by_month.pdf", title = "Retrospective discrepancy by target month"),
      cutoff_source_diagnostic = list(
        enabled = TRUE,
        cutoff_id = cutoff_id,
        filename = sprintf("cutoff_source_diagnostic_%s.pdf", gsub("-", "", cutoff_date)),
        title = sprintf("Audited GloFAS diagnostic around %s", cutoff_date),
        window_before_days = 30L,
        window_after_days = 30L,
        max_members = 51L
      )
    )
  )
  figure_specs_path <- file.path(cfg_dir, "figure_specs.yaml")
  app_write_yaml(figure_specs, figure_specs_path)

  cfg <- app_read_config(app_path("application/config/glofas_dec25_authoritative_source_figures.yaml"))
  cfg$application_name <- sprintf("glofas_authoritative_source_figures_%s", gsub("-", "", cutoff_date))
  cfg$description <- sprintf("Generated audited source-diagnostic configuration for cutoff %s.", cutoff_date)
  cfg$paths$input_bundle <- app_prefer_repo_relative_path(input_bundle_path)
  cfg$paths$cutoffs <- app_prefer_repo_relative_path(cutoffs_path)
  cfg$paths$figure_specs <- app_prefer_repo_relative_path(figure_specs_path)
  cfg$paths$cache <- file.path("application/cache/authoritative_cutoffs", sprintf("cutoff_date=%s", cutoff_date))
  cfg$.__config_path__ <- NULL
  cfg_path <- file.path(cfg_dir, "config.yaml")
  app_write_yaml(cfg, cfg_path)

  list(config = cfg_path, input_bundle = input_bundle_path, cutoffs = cutoffs_path, figure_specs = figure_specs_path)
}

run_stage <- function(script, config_path, run_id, extra_args = character()) {
  cmd <- c(script, "--config", app_prefer_repo_relative_path(config_path), "--run_id", run_id, extra_args)
  status <- system2("Rscript", cmd)
  if (!identical(status, 0L)) {
    stop(sprintf("Stage failed for %s: %s", run_id, script), call. = FALSE)
  }
}

rows <- list()
for (cutoff_date in cutoff_dates) {
  cutoff_run_id <- sprintf("%s__cutoff-%s", args$run_id, gsub("-", "", cutoff_date))
  cutoff_source_root <- file.path(bundle_root, sprintf("cutoff_date=%s", cutoff_date))
  bundle_dir <- file.path(output_bundle_root, sprintf("cutoff_date=%s", cutoff_date))
  cfg_dir <- file.path(generated_config_root, sprintf("cutoff_date=%s", cutoff_date))
  start <- proc.time()[["elapsed"]]
  status <- "completed"
  message <- ""
  result_summary <- NULL
  tryCatch({
    cfg_files <- write_cutoff_config_files(cutoff_date, bundle_dir, cfg_dir)
    cfg <- app_read_config(cfg_files$config)
    run_dirs <- app_create_run_dirs(cfg, cutoff_run_id)

    audit <- app_audit_authoritative_source_bundle(
      bundle_root = bundle_root,
      cutoff_date = cutoff_date,
      requirements_path = requirements_path,
      extra_roots = extra_roots
    )
    app_write_authoritative_source_audit(audit, run_dirs)
    if (!audit$ok) {
      failed <- audit$audit[audit$audit$required & audit$audit$status != "ok", , drop = FALSE]
      stop(paste(sprintf("%s: %s", failed$component, failed$detail), collapse = "; "), call. = FALSE)
    }

    materialized <- app_materialize_authoritative_cutoff_bundle(
      source_root = cutoff_source_root,
      cutoff_date = cutoff_date,
      bundle_root = bundle_dir,
      station_id = args$station_id,
      requirements_path = requirements_path,
      overwrite = TRUE
    )
    result_summary <- materialized$summary

    run_stage("application/scripts/00_register_input_bundle.R", cfg_files$config, cutoff_run_id, c("--bundle_config", cfg_files$input_bundle))
    run_stage("application/scripts/00_check_inputs.R", cfg_files$config, cutoff_run_id)
    run_stage("application/scripts/00_audit_input_bundle.R", cfg_files$config, cutoff_run_id)
    run_stage("application/scripts/01_build_panel.R", cfg_files$config, cutoff_run_id)
    run_stage("application/scripts/02_make_input_figures.R", cfg_files$config, cutoff_run_id)
    if (app_as_bool(args$collect_handoff)) {
      run_stage(
        "application/scripts/02_collect_handoff_figures.R",
        cfg_files$config,
        cutoff_run_id,
        c("--cutoff_date", cutoff_date, "--handoff_run_root", args$extra_root)
      )
    }
  }, error = function(e) {
    status <<- "failed"
    message <<- conditionMessage(e)
    if (app_as_bool(args$stop_on_failure)) stop(message, call. = FALSE)
  })
  elapsed <- proc.time()[["elapsed"]] - start
  rows[[length(rows) + 1L]] <- data.frame(
    cutoff_date = cutoff_date,
    run_id = cutoff_run_id,
    status = status,
    message = message,
    runtime_seconds = elapsed,
    bundle_root = app_prefer_repo_relative_path(bundle_dir),
    config_root = app_prefer_repo_relative_path(cfg_dir),
    glofas_source_id = if (!is.null(result_summary)) result_summary$glofas_source_id[[1L]] else NA_character_,
    n_glofas_ensemble_rows = if (!is.null(result_summary)) result_summary$n_glofas_ensemble_rows[[1L]] else NA_integer_,
    n_glofas_members = if (!is.null(result_summary)) result_summary$n_glofas_members[[1L]] else NA_integer_,
    stringsAsFactors = FALSE
  )
}

summary <- do.call(rbind, rows)
app_write_csv(summary, file.path(summary_tables_dir, "authoritative_source_cutoff_diagnostic_summary.csv"))
app_write_git_state(file.path(summary_run_dir, "manifest", "git_state.txt"))
app_write_session_info(file.path(summary_run_dir, "manifest", "session_info.txt"))
cat(file.path(summary_tables_dir, "authoritative_source_cutoff_diagnostic_summary.csv"), "\n")
