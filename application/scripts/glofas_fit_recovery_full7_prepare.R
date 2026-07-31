#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))

args <- app_parse_args(list(
  finalists = "local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731/tables/stage_a_finalists_recommended.csv",
  triage_root = "local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_full7_20260731",
  require_approval = TRUE
))
resolve_repo <- function(path, must_work = FALSE) {
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

finalists_path <- resolve_repo(args$finalists, must_work = TRUE)
triage_root <- resolve_repo(args$triage_root, must_work = TRUE)
output_root <- resolve_repo(args$output_root, must_work = FALSE)
finalists <- app_read_csv(finalists_path)
required <- c("candidate_id", "recommended", "approved_for_full7")
missing <- setdiff(required, names(finalists))
if (length(missing)) stop(sprintf("Finalist registry lacks: %s.", paste(missing, collapse = ", ")), call. = FALSE)
finalists <- finalists[app_as_bool_vec(finalists$recommended), , drop = FALSE]
if (app_as_bool(args$require_approval)) finalists <- finalists[app_as_bool_vec(finalists$approved_for_full7), , drop = FALSE]
if (!nrow(finalists)) stop("No finalist has explicit full-seven approval.", call. = FALSE)
if (nrow(finalists) > 2L) stop("Full-seven completion is capped at two approved finalists.", call. = FALSE)

source_manifest <- app_glofas_selection_validate_source_manifest(
  app_read_csv(file.path(triage_root, "quantile_source_manifest_completed.csv")),
  require_complete = TRUE
)
required_source_levels <- c(0.05, 0.50, 0.95)
for (candidate_id in finalists$candidate_id) {
  levels <- sort(source_manifest$quantile_level[source_manifest$candidate_id == candidate_id])
  if (!isTRUE(all.equal(levels, required_source_levels, tolerance = 1e-12))) {
    stop(sprintf("Candidate %s does not have an exact completed p05/p50/p95 source set.", candidate_id), call. = FALSE)
  }
}

for (dir in c("candidates", "common_cache", "runs", "logs", "generated", "scores", "status", "tables", "figures", "cleanup")) {
  app_ensure_dir(file.path(output_root, dir))
}
triage_panel <- file.path(triage_root, "common_cache", "application_panel.rds")
full7_panel <- file.path(output_root, "common_cache", "application_panel.rds")
if (!file.exists(triage_panel)) stop("The audited Stage A application panel is missing.", call. = FALSE)
if (!file.exists(full7_panel) && !file.copy(triage_panel, full7_panel, copy.mode = TRUE, copy.date = TRUE)) {
  stop("Could not copy the audited application panel for full-seven completion.", call. = FALSE)
}
if (!identical(app_sha256_file(triage_panel), app_sha256_file(full7_panel))) {
  stop("The full-seven application-panel hash does not match Stage A.", call. = FALSE)
}

missing_levels <- c(0.15, 0.35, 0.65, 0.80)
runtime_rows <- list()
full_source_rows <- list()
priority <- 0L
for (candidate_id in finalists$candidate_id) {
  source_block <- source_manifest[source_manifest$candidate_id == candidate_id, , drop = FALSE]
  full_source_rows[[length(full_source_rows) + 1L]] <- source_block
  p50 <- source_block[abs(source_block$quantile_level - 0.5) < 1e-12, , drop = FALSE]
  p50_config <- app_read_config(p50$config_path[[1L]])
  p50_model_grid <- app_read_csv(p50$model_grid_path[[1L]])
  if (!identical(app_sha256_file(p50$fit_object[[1L]]), p50$fit_object_sha256[[1L]])) {
    stop(sprintf("The p50 warm-start object changed for %s.", candidate_id), call. = FALSE)
  }
  for (quantile_level in missing_levels) {
    priority <- priority + 1L
    quantile_id <- app_glofas_selection_quantile_id(quantile_level)
    worker_id <- paste(candidate_id, quantile_id, sep = "__")
    candidate_root <- file.path(output_root, "candidates", candidate_id, quantile_id)
    app_ensure_dir(candidate_root)
    quantile_grid_path <- file.path(candidate_root, paste0("quantile_grid_", quantile_id, ".csv"))
    app_write_csv(data.frame(
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      role = "interior_quantile",
      enabled = TRUE,
      stringsAsFactors = FALSE
    ), quantile_grid_path)

    fit_id <- paste0("qdesn_fit_recovery_full7_", candidate_id, "_", quantile_id)
    raw_fit_id <- paste0("raw_glofas_fit_recovery_full7_", candidate_id, "_", quantile_id)
    model_grid <- p50_model_grid
    raw_row <- model_grid$model_family == "raw_glofas"
    qdesn_row <- model_grid$model_family == "qdesn_glofas_discrepancy"
    if (sum(raw_row) != 1L || sum(qdesn_row) != 1L) stop("The p50 source model grid is not a one-pair grid.", call. = FALSE)
    model_grid$fit_id[raw_row] <- raw_fit_id
    model_grid$model_id[raw_row] <- raw_fit_id
    model_grid$fit_id[qdesn_row] <- fit_id
    model_grid$model_id[qdesn_row] <- fit_id
    model_grid$quantile_level <- quantile_level
    model_grid$notes <- paste("Independent full-seven completion", quantile_id, "for", candidate_id)
    model_grid_path <- file.path(candidate_root, paste0("model_grid_", quantile_id, ".csv"))
    app_write_csv(model_grid, model_grid_path)

    cfg <- p50_config
    cfg$.__config_path__ <- NULL
    cfg$application_name <- paste0("glofas_fit_recovery_full7_", candidate_id, "_", quantile_id)
    cfg$description <- paste("Independent", quantile_id, "full-seven completion for", candidate_id)
    cfg$paths$model_grid <- model_grid_path
    cfg$paths$quantile_grid <- quantile_grid_path
    cfg$paths$cache <- file.path(output_root, "common_cache")
    cfg$paths$runs <- file.path(output_root, "runs")
    cfg$paths$logs <- file.path(output_root, "logs")
    cfg$paths$generated_outputs <- file.path(output_root, "generated")
    cfg$inference$vb_ld$warm_start <- list(
      enabled = TRUE,
      fit_object = p50$fit_object[[1L]],
      use_theta = TRUE,
      use_future = FALSE,
      use_sigma = FALSE,
      require_theta = TRUE,
      require_future = FALSE,
      require_sigma = FALSE,
      covariance_jitter = 1.0e-8
    )
    cfg$execution$artifacts <- list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      retain_prediction_design_object = TRUE,
      retain_reference_fit_object = TRUE
    )
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- paste("Approved full-seven completion for", worker_id)
    config_path <- file.path(candidate_root, paste0("config_", quantile_id, ".yaml"))
    app_write_yaml(cfg, config_path)

    run_id <- paste0("glofas_fit_recovery_full7_20260731_", candidate_id, "_", quantile_id)
    run_dir <- file.path(output_root, "runs", run_id)
    fit_object <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
    runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
      candidate_id = worker_id,
      base_candidate_id = candidate_id,
      priority = priority,
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      config_path = config_path,
      config_sha256 = app_sha256_file(config_path),
      model_grid_path = model_grid_path,
      model_grid_sha256 = app_sha256_file(model_grid_path),
      run_id = run_id,
      run_dir = run_dir,
      log_path = file.path(output_root, "logs", paste0(worker_id, ".log")),
      warm_start_source_fit_object = p50$fit_object[[1L]],
      warm_start_source_sha256 = p50$fit_object_sha256[[1L]],
      expected_n_theta = p50$expected_n_theta[[1L]],
      retain_heavy = TRUE,
      status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
    full_source_rows[[length(full_source_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      role = p50$role[[1L]],
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      source_kind = "new_full7_fit",
      run_id = run_id,
      run_dir = run_dir,
      config_path = config_path,
      config_sha256 = app_sha256_file(config_path),
      model_grid_path = model_grid_path,
      model_grid_sha256 = app_sha256_file(model_grid_path),
      history_path = file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv"),
      fit_object = fit_object,
      fit_object_sha256 = NA_character_,
      warm_start_source_fit_object = p50$fit_object[[1L]],
      warm_start_source_sha256 = p50$fit_object_sha256[[1L]],
      expected_n_theta = p50$expected_n_theta[[1L]],
      status = "prepared",
      stringsAsFactors = FALSE
    )
  }
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
full_source_manifest <- app_bind_rows_fill(full_source_rows)
full_source_manifest <- full_source_manifest[order(full_source_manifest$candidate_id, full_source_manifest$quantile_level), , drop = FALSE]
full_source_manifest <- app_glofas_selection_validate_source_manifest(full_source_manifest, require_complete = FALSE)
app_write_csv(runtime_manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(full_source_manifest, file.path(output_root, "quantile_source_manifest_prepared.csv"))
app_write_csv(finalists, file.path(output_root, "approved_finalists_snapshot.csv"))
app_write_csv(data.frame(
  field = c("prepared_at", "repo_head", "finalists_sha256", "triage_source_manifest_sha256", "panel_sha256", "launch_status"),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    app_sha256_file(finalists_path),
    app_sha256_file(file.path(triage_root, "quantile_source_manifest_completed.csv")),
    app_sha256_file(full7_panel),
    "prepared_not_launched"
  ),
  stringsAsFactors = FALSE
), file.path(output_root, "provenance.csv"))
writeLines(c(
  "Full-seven completion is prepared but not launched.",
  "Only candidates with approved_for_full7=true were materialized.",
  "Launch the bounded scheduler explicitly after reviewing this manifest.",
  "No historical pseudo-cutoff or article-facing promotion is implied."
), file.path(output_root, "README.txt"))
cat(file.path(output_root, "runtime_manifest.csv"), "\n")
