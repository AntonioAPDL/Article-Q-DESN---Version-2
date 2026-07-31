#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  finalists = "local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731/tables/stage_a_finalists_recommended.csv",
  cutoff_registry = "application/config/glofas_fit_recovery_validation_cutoffs_20260731.csv",
  p50_recovery_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_blocked_20260731",
  authoritative_data_root = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/data_local",
  require_approval = TRUE
))
resolve_repo <- function(path, must_work = FALSE) {
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}
resolve_recorded <- function(path, must_work = TRUE) {
  if (grepl("^/", path)) normalizePath(path, mustWork = must_work) else normalizePath(app_path(path), mustWork = must_work)
}
set_oracle_covariates <- function(cfg) {
  cfg$covariates$source_policy <- NULL
  cfg$covariates$future_policy <- "oracle_realized"
  cfg$covariates$allow_realized_future <- TRUE
  cfg$covariates$allow_realized_future_blend <- NULL
  cfg$covariates$forecast$provider <- "realized_future_oracle"
  cfg$covariates$forecast$handoff_root <- NULL
  for (variable in c("ppt", "soil")) {
    cfg$covariates[[variable]]$noisy_blend <- NULL
    cfg$covariates[[variable]]$observed_blend <- NULL
    cfg$covariates[[variable]]$forecast_noise <- list(enabled = FALSE)
    cfg$covariates[[variable]]$realized_future_correction <- list(enabled = TRUE, observed_weight = 1)
  }
  cfg
}
profile_manifest_row <- function(input_id, source_name, source_type, path, upstream_reference, required, notes) {
  x <- app_read_csv(path)
  date_columns <- intersect(c("date", "origin_date", "target_date"), names(x))
  dates <- as.Date(character())
  for (name in date_columns) dates <- c(dates, suppressWarnings(as.Date(x[[name]])))
  dates <- dates[!is.na(dates)]
  data.frame(
    input_id = input_id,
    source_name = source_name,
    source_type = source_type,
    local_path = normalizePath(path, mustWork = TRUE),
    upstream_reference = upstream_reference,
    date_min = if (length(dates)) as.character(min(dates)) else NA_character_,
    date_max = if (length(dates)) as.character(max(dates)) else NA_character_,
    cutoff_date = NA_character_,
    row_count = nrow(x),
    column_count = ncol(x),
    sha256 = app_sha256_file(path),
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    notes = notes,
    required = required,
    stringsAsFactors = FALSE
  )
}

finalists_path <- resolve_repo(args$finalists, must_work = TRUE)
cutoff_path <- resolve_repo(args$cutoff_registry, must_work = TRUE)
p50_root <- resolve_repo(args$p50_recovery_root, must_work = TRUE)
output_root <- resolve_repo(args$output_root, must_work = FALSE)
data_root <- normalizePath(args$authoritative_data_root, mustWork = TRUE)
finalists <- app_read_csv(finalists_path)
if (!all(c("candidate_id", "recommended", "approved_for_blocked_validation") %in% names(finalists))) {
  stop("The finalist registry lacks blocked-validation approval fields.", call. = FALSE)
}
finalists <- finalists[app_as_bool_vec(finalists$recommended), , drop = FALSE]
if (app_as_bool(args$require_approval)) {
  finalists <- finalists[app_as_bool_vec(finalists$approved_for_blocked_validation), , drop = FALSE]
}
if (!nrow(finalists)) stop("No finalist has explicit blocked-validation approval.", call. = FALSE)
if (nrow(finalists) > 3L) stop("Blocked validation is capped at two finalists plus one control.", call. = FALSE)

cutoffs <- app_read_csv(cutoff_path)
cutoffs <- cutoffs[app_as_bool_vec(cutoffs$enabled), , drop = FALSE]
if (!nrow(cutoffs)) stop("No blocked-validation cutoff is enabled.", call. = FALSE)
p50_runtime <- app_read_csv(file.path(p50_root, "runtime_manifest.csv"))
if (!all(finalists$candidate_id %in% p50_runtime$candidate_id)) {
  stop("One or more approved finalists lack a completed p50 recovery source.", call. = FALSE)
}

for (dir in c("inputs", "candidates", "common_cache", "runs", "logs", "generated", "scores", "status", "tables", "figures", "cleanup")) {
  app_ensure_dir(file.path(output_root, dir))
}
schema_path <- app_path("application/manifests/expected_schema.yaml")
cutoff_assets <- list()

for (i in seq_len(nrow(cutoffs))) {
  cutoff <- cutoffs[i, , drop = FALSE]
  cutoff_id <- cutoff$cutoff_id[[1L]]
  origin <- as.Date(cutoff$origin_date[[1L]])
  declared_bundle <- as.character(cutoff$bundle_dir[[1L]])
  relative_bundle <- sub("^application/data_local/?", "", declared_bundle)
  bundle_dir <- normalizePath(file.path(data_root, relative_bundle), mustWork = TRUE)
  input_root <- file.path(output_root, "inputs", cutoff_id)
  app_ensure_dir(input_root)

  climate_path <- file.path(bundle_dir, "covariates", "climate_covariates.csv")
  climate <- app_read_csv(climate_path)
  required_climate <- c("date", "precipitation_mm", "soil_moisture")
  if (!all(required_climate %in% names(climate))) {
    stop(sprintf("Cutoff %s lacks the required realized climate columns.", cutoff_id), call. = FALSE)
  }
  ppt_soil_path <- file.path(input_root, "ppt_soil_covariates.csv")
  app_write_csv(data.frame(
    date = as.Date(climate$date),
    ppt = as.numeric(climate$precipitation_mm),
    soil = as.numeric(climate$soil_moisture),
    stringsAsFactors = FALSE
  ), ppt_soil_path)

  paths <- list(
    reference_gauge = file.path(bundle_dir, "reference", "reference_gauge.csv"),
    glofas_retrospective = file.path(bundle_dir, "glofas", "glofas_retrospective.csv"),
    glofas_ensemble = file.path(bundle_dir, "glofas", "glofas_ensemble.csv"),
    climate_covariates = climate_path,
    ppt_soil_covariates = ppt_soil_path
  )
  if (!all(file.exists(unlist(paths)))) stop(sprintf("Cutoff %s has missing input files.", cutoff_id), call. = FALSE)
  input_manifest <- app_bind_rows_fill(list(
    profile_manifest_row("reference_gauge", "reference gauge streamflow", "observation", paths$reference_gauge, bundle_dir, TRUE, "Frozen historical pseudo-cutoff reference series."),
    profile_manifest_row("glofas_retrospective", "GloFAS retrospective streamflow", "retrospective_forecast", paths$glofas_retrospective, bundle_dir, TRUE, "Frozen long-history GloFAS v3.1 retrospective series."),
    profile_manifest_row("glofas_ensemble", "GloFAS issued ensemble", "ensemble_forecast", paths$glofas_ensemble, bundle_dir, TRUE, "Issued ensemble at the historical pseudo-cutoff."),
    profile_manifest_row("climate_covariates", "diagnostic climate covariates", "covariate", paths$climate_covariates, bundle_dir, FALSE, "Frozen realized climate table retained for provenance."),
    profile_manifest_row("ppt_soil_covariates", "precipitation and soil covariates", "covariate", paths$ppt_soil_covariates, climate_path, FALSE, "Model-facing realized ppt/soil table materialized for an oracle diagnostic only.")
  ))
  input_manifest_path <- file.path(input_root, "input_manifest.csv")
  app_write_csv(input_manifest[, app_required_manifest_columns(), drop = FALSE], input_manifest_path)
  validation <- app_validate_input_manifest(input_manifest_path, schema_path, require_files = TRUE)
  if (!validation$ok) stop(paste(validation$issues, collapse = "\n"), call. = FALSE)

  bundle_manifest <- input_manifest
  bundle_manifest$bundle_id <- paste0("glofas_fit_recovery_blocked_", cutoff_id)
  bundle_manifest$bundle_root <- bundle_dir
  bundle_manifest$relative_path <- vapply(paths, function(path) {
    if (startsWith(normalizePath(path, mustWork = TRUE), paste0(bundle_dir, .Platform$file.sep))) {
      substring(normalizePath(path, mustWork = TRUE), nchar(bundle_dir) + 2L)
    } else {
      normalizePath(path, mustWork = TRUE)
    }
  }, character(1L))
  bundle_manifest$local_path <- input_manifest$local_path
  bundle_manifest$file_size_bytes <- as.numeric(file.info(input_manifest$local_path)$size)
  bundle_manifest$modified_time <- format(file.info(input_manifest$local_path)$mtime, "%Y-%m-%d %H:%M:%S %Z")
  bundle_manifest$registered_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  bundle_manifest$status <- "ok"
  bundle_manifest$message <- NA_character_
  bundle_manifest_path <- file.path(input_root, "input_bundle_manifest.csv")
  app_write_csv(bundle_manifest, bundle_manifest_path)

  ensemble <- app_read_csv(paths$glofas_ensemble)
  horizon_max <- max(as.integer(ensemble$horizon), na.rm = TRUE)
  target_max <- max(as.Date(ensemble$target_date), na.rm = TRUE)
  cutoff_table_path <- file.path(input_root, "cutoffs.csv")
  app_write_csv(data.frame(
    cutoff_id = cutoff_id,
    origin_date = origin,
    train_start = as.Date("1979-02-01"),
    train_end = origin,
    eval_start = origin + 1L,
    eval_end = target_max,
    horizon_min = min(as.integer(ensemble$horizon), na.rm = TRUE),
    horizon_max = horizon_max,
    split = "blocked_oracle_diagnostic",
    enabled = TRUE,
    notes = "Cold-start historical replay; realized future ppt/soil are oracle diagnostic covariates.",
    stringsAsFactors = FALSE
  ), cutoff_table_path)
  input_bundle_path <- file.path(input_root, "input_bundle.yaml")
  app_write_yaml(list(
    version = 0.1,
    bundle_id = paste0("glofas_fit_recovery_blocked_", cutoff_id),
    description = "Frozen historical pseudo-cutoff bundle for cold-start portability diagnostics.",
    bundle_root = bundle_dir,
    copy_files = FALSE,
    manifest_output = input_manifest_path,
    bundle_manifest_output = bundle_manifest_path
  ), input_bundle_path)
  cutoff_assets[[cutoff_id]] <- list(
    origin = origin,
    input_manifest_path = input_manifest_path,
    bundle_manifest_path = bundle_manifest_path,
    input_bundle_path = input_bundle_path,
    cutoff_table_path = cutoff_table_path,
    cache_dir = file.path(output_root, "common_cache", cutoff_id),
    horizon_max = horizon_max,
    target_max = target_max,
    bundle_dir = bundle_dir
  )
}

runtime_rows <- list()
priority <- 0L
panel_audit <- list()
for (cutoff_id in names(cutoff_assets)) {
  asset <- cutoff_assets[[cutoff_id]]
  first_source <- p50_runtime[p50_runtime$candidate_id == finalists$candidate_id[[1L]], , drop = FALSE]
  panel_cfg <- set_oracle_covariates(app_read_config(resolve_recorded(first_source$config_path[[1L]])))
  panel_cfg$.__config_path__ <- NULL
  panel_cfg$paths$input_bundle <- asset$input_bundle_path
  panel_cfg$paths$input_bundle_manifest <- asset$bundle_manifest_path
  panel_cfg$paths$input_manifest <- asset$input_manifest_path
  panel_cfg$paths$cutoffs <- asset$cutoff_table_path
  panel_cfg$paths$cache <- asset$cache_dir
  app_ensure_dir(asset$cache_dir)
  policy <- app_validate_covariate_source_policy(
    panel_cfg,
    cutoff_row = data.frame(origin_date = asset$origin),
    stop_on_failure = FALSE
  )
  if (!identical(policy$status[[1L]], "PASS") ||
      !identical(policy$future_policy[[1L]], "oracle_realized") ||
      !isTRUE(policy$uses_realized_future[[1L]])) {
    stop(sprintf("Cutoff %s failed the explicit oracle covariate-policy gate.", cutoff_id), call. = FALSE)
  }
  validated <- app_validate_input_manifest(asset$input_manifest_path, schema_path, require_files = TRUE)
  panel <- app_build_application_panel(panel_cfg, validated$manifest, validated$schema)
  app_validate_panel(panel, validated$schema)
  panel_path <- file.path(asset$cache_dir, "application_panel.rds")
  saveRDS(panel, panel_path)
  panel_audit[[length(panel_audit) + 1L]] <- cbind(
    data.frame(cutoff_id = cutoff_id, panel_path = panel_path, panel_sha256 = app_sha256_file(panel_path), stringsAsFactors = FALSE),
    app_panel_summary(panel)
  )

  for (candidate_id in finalists$candidate_id) {
    priority <- priority + 1L
    source_row <- p50_runtime[p50_runtime$candidate_id == candidate_id, , drop = FALSE]
    if (nrow(source_row) != 1L || !file.exists(file.path(source_row$run_dir[[1L]], ".fit_recovery_complete"))) {
      stop(sprintf("Candidate %s lacks a completed p50 source.", candidate_id), call. = FALSE)
    }
    source_cfg <- app_read_config(resolve_recorded(source_row$config_path[[1L]]))
    source_grid <- app_read_csv(resolve_recorded(source_row$model_grid_path[[1L]]))
    candidate_root <- file.path(output_root, "candidates", candidate_id, cutoff_id)
    app_ensure_dir(candidate_root)
    quantile_grid_path <- file.path(candidate_root, "quantile_grid_p50.csv")
    app_write_csv(data.frame(quantile_id = "p50", quantile_level = 0.5, role = "median", enabled = TRUE), quantile_grid_path)
    fit_id <- paste0("qdesn_fit_recovery_blocked_", candidate_id, "_", cutoff_id, "_p50")
    raw_fit_id <- paste0("raw_glofas_fit_recovery_blocked_", candidate_id, "_", cutoff_id, "_p50")
    raw_row <- source_grid$model_family == "raw_glofas"
    qdesn_row <- source_grid$model_family == "qdesn_glofas_discrepancy"
    source_grid$fit_id[raw_row] <- raw_fit_id
    source_grid$model_id[raw_row] <- raw_fit_id
    source_grid$fit_id[qdesn_row] <- fit_id
    source_grid$model_id[qdesn_row] <- fit_id
    source_grid$quantile_level <- 0.5
    source_grid$notes <- paste("Cold-start", cutoff_id, "oracle portability diagnostic for", candidate_id)
    model_grid_path <- file.path(candidate_root, "model_grid_p50.csv")
    app_write_csv(source_grid, model_grid_path)

    cfg <- set_oracle_covariates(source_cfg)
    cfg$.__config_path__ <- NULL
    cfg$application_name <- paste0("glofas_fit_recovery_blocked_", candidate_id, "_", cutoff_id)
    cfg$description <- paste(
      "Cold-start p50 historical pseudo-cutoff replay for", candidate_id, "at", asset$origin,
      "using explicitly non-deployable oracle-realized ppt/soil covariates."
    )
    cfg$paths$input_bundle <- asset$input_bundle_path
    cfg$paths$input_bundle_manifest <- asset$bundle_manifest_path
    cfg$paths$input_manifest <- asset$input_manifest_path
    cfg$paths$cutoffs <- asset$cutoff_table_path
    cfg$paths$quantile_grid <- quantile_grid_path
    cfg$paths$model_grid <- model_grid_path
    cfg$paths$data_local <- data_root
    cfg$paths$cache <- asset$cache_dir
    cfg$paths$runs <- file.path(output_root, "runs")
    cfg$paths$logs <- file.path(output_root, "logs")
    cfg$paths$generated_outputs <- file.path(output_root, "generated")
    cfg$forecast_protocol$default_horizon_max <- asset$horizon_max
    cfg$inference$vb_ld$warm_start <- list(enabled = FALSE)
    cfg$post_analysis$run_after_outputs <- TRUE
    cfg$execution$artifacts <- list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      retain_prediction_design_object = TRUE,
      retain_reference_fit_object = TRUE
    )
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- paste("Approved cold-start blocked diagnostic for", candidate_id, cutoff_id)
    config_path <- file.path(candidate_root, "config_p50.yaml")
    app_write_yaml(cfg, config_path)
    run_id <- paste0("glofas_fit_recovery_blocked_20260731_", candidate_id, "_", cutoff_id)
    runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
      candidate_id = paste(candidate_id, cutoff_id, sep = "__"),
      base_candidate_id = candidate_id,
      cutoff_id = cutoff_id,
      origin_date = as.character(asset$origin),
      priority = priority,
      config_path = config_path,
      config_sha256 = app_sha256_file(config_path),
      model_grid_path = model_grid_path,
      model_grid_sha256 = app_sha256_file(model_grid_path),
      run_id = run_id,
      run_dir = file.path(output_root, "runs", run_id),
      log_path = file.path(output_root, "logs", paste0(candidate_id, "__", cutoff_id, ".log")),
      future_policy = "oracle_realized",
      source_provider = "realized_future_oracle",
      cold_start = TRUE,
      status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
  }
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
app_write_csv(runtime_manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(app_bind_rows_fill(panel_audit), file.path(output_root, "tables", "blocked_panel_audit.csv"))
app_write_csv(finalists, file.path(output_root, "approved_finalists_snapshot.csv"))
app_write_csv(cutoffs, file.path(output_root, "cutoff_registry_snapshot.csv"))
app_write_csv(data.frame(
  field = c("prepared_at", "repo_head", "finalists_sha256", "cutoff_registry_sha256", "p50_runtime_manifest_sha256", "launch_status"),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(finalists_path),
    app_sha256_file(cutoff_path),
    app_sha256_file(file.path(p50_root, "runtime_manifest.csv")),
    "prepared_not_launched"
  ),
  stringsAsFactors = FALSE
), file.path(output_root, "provenance.csv"))
writeLines(c(
  "Historical pseudo-cutoff validation is prepared but not launched.",
  "Every fit is cold-started; no 2022-12-25 variational state is reused.",
  "Realized future ppt/soil values are explicitly labelled oracle_realized and are diagnostic-only.",
  "Launch requires a separate bounded-scheduler command after Stage A approval."
), file.path(output_root, "README.txt"))
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
