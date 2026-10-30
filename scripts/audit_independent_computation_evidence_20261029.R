#!/usr/bin/env Rscript
# Metadata-only inventory. This script never loads a fitted object or runs a model.
options(stringsAsFactors = FALSE, digits = 17)
args <- commandArgs(TRUE)
option <- function(name) {
  i <- match(name, args)
  if (is.na(i) || i == length(args)) stop("Supply ", name, call. = FALSE)
  args[[i + 1L]]
}
validation <- normalizePath(option("--validation-root"), mustWork = TRUE)
bundle <- normalizePath(option("--historical-bundle"), mustWork = TRUE)
sha <- function(path) unname(tools::sha256sum(path)[[1L]])
read_json <- function(path) jsonlite::read_json(path, simplifyVector = TRUE)
value <- function(x, default = NA) if (is.null(x) || !length(x)) default else x[[1L]]
same_hash <- function(path, expected) {
  stopifnot(file.exists(path), identical(sha(path), as.character(expected)))
}
fit_path <- "tables/independent_fit_preserved_300_500_v1.csv"
forecast_path <- "tables/independent_forecast_300_500_v1.csv"
fit <- read.csv(fit_path)
forecast <- read.csv(forecast_path)
identity <- c("inference", "model_variant", "family", "tau", "replay_id")
active <- unique(rbind(fit[identity], forecast[identity]))
active <- active[do.call(order, active[identity]), ]
key <- function(x) do.call(paste, c(x[identity], sep = "|"))
active$fit_metric_active <- key(active) %in% key(fit)
active$forecast_metrics_active <- key(active) %in% key(forecast)
stopifnot(nrow(active) == 90L,
  sum(grepl("^qdesn", active$model_variant)) == 54L,
  length(unique(forecast$replay_id)) == 44L)

promotion <- file.path(validation, "validation/fitforecast_v2/promotions/independent_forecast_300_500_v1")
locator_path <- file.path(promotion, "protected_source_locator.csv")
promotion_manifest_path <- file.path(promotion, "artifact_manifest.csv")
promotion_manifest <- read.csv(promotion_manifest_path)
expected <- promotion_manifest$sha256[basename(promotion_manifest$path) == basename(locator_path)]
stopifnot(length(expected) == 1L)
same_hash(locator_path, expected)
locator <- read.csv(locator_path)
bundle_manifest_path <- file.path(bundle, "bundle_file_manifest.csv")
bundle_manifest <- read.csv(bundle_manifest_path)
rolling_root <- file.path(validation,
  "validation/fitforecast_v2/promotions/independent_exdqlm_mcmc_rolling_state_fix_v1_20260829")
rolling_manifest_path <- file.path(rolling_root, "manifests/job_manifest.csv")
rolling_artifacts <- read.csv(file.path(rolling_root, "artifact_manifest.csv"))
same_hash(rolling_manifest_path,
  rolling_artifacts$sha256[rolling_artifacts$relative_path == "manifests/job_manifest.csv"])
rolling <- read.csv(rolling_manifest_path)
bundle_pin <- function(relative) {
  e <- bundle_manifest$sha256[bundle_manifest$relative_path == relative]
  stopifnot(length(e) == 1L)
  p <- file.path(bundle, relative)
  same_hash(p, e)
  p
}
receipts <- list()
add <- function(a, stage, task, config_path, status_path, expected_config = NULL,
                expected_status = NULL) {
  if (!file.exists(config_path) || !file.exists(status_path)) return(invisible(NULL))
  if (!is.null(expected_config)) same_hash(config_path, expected_config)
  if (!is.null(expected_status)) same_hash(status_path, expected_status)
  cfg <- read_json(config_path)
  csv_status <- grepl("[.]csv$", status_path)
  status <- if (csv_status) as.list(read.csv(status_path)[1L, ]) else read_json(status_path)
  if (csv_status) {
    stopifnot(status$status == "done", status$family == a$family,
      status$tau == a$tau, status$model_variant == a$model_variant,
      status$inference == a$inference)
    status$status <- "SUCCESS"
    status$elapsed_seconds <- status$runtime_sec
    status$replay_id <- a$replay_id
  }
  stopifnot(value(status$status) %in% c("COMPLETE", "SUCCESS"))
  engine <- value(cfg$engine, value(status$engine,
    if (grepl("^qdesn", a$model_variant)) "qdesn" else "dqlm"))
  config <- if (is.null(cfg$config)) cfg else cfg$config
  m <- if (identical(engine, "qdesn")) config$inference$mcmc else config$budget$mcmc
  v <- if (identical(engine, "qdesn")) config$inference$vb else config$budget$vb
  reconstructed <- identical(stage, "forecast_reconstruction")
  if (reconstructed) {
    stopifnot(identical(as.character(cfg$task$replay_id), a$replay_id))
    retention <- file.path(dirname(status_path), "retention_manifest.csv")
    same_hash(retention, status$retention_manifest_sha256)
    stopifnot(identical(as.character(status$contract_sha256), sha(config_path)))
  } else {
    stopifnot(identical(as.character(status$replay_id), a$replay_id),
      identical(as.character(cfg$inference), a$inference),
      identical(as.character(cfg$model_variant), a$model_variant))
    if (!csv_status) stopifnot(identical(as.character(status$config_sha256), sha(config_path)))
  }
  fit_calls <- if (reconstructed) value(status$fit_calls) else NA_integer_
  timing_scope <- if (!reconstructed) "historical_fit_forecast_and_metric_workflow" else
    if (!is.na(fit_calls) && fit_calls == 0L) "cached_forecast_rescoring_only" else
      "reconstructed_fit_forecast_and_export_workflow"
  receipts[[length(receipts) + 1L]] <<- data.frame(a[identity],
    evidence_stage = stage, task_id = task,
    config_sha256 = sha(config_path), status_sha256 = sha(status_path),
    status_hash_previously_pinned = !is.null(expected_status),
    n_burn_requested = if (a$inference == "mcmc") value(m$n_burn) else NA,
    n_mcmc_requested = if (a$inference == "mcmc") value(m$n_mcmc) else NA,
    thin_requested = if (a$inference == "mcmc") value(m$thin) else NA,
    vb_max_iter_requested = if (a$inference == "vb") value(v$max_iter) else NA,
    package_version = value(cfg$package_version,
      value(cfg$package_contract$version, "NOT_RETAINED_IN_THIS_RECEIPT")),
    fit_calls = fit_calls, elapsed_seconds = value(status$elapsed_seconds),
    timing_scope = timing_scope, fit_only_timing = FALSE,
    score_draws_exported = if (reconstructed)
      locator$n_draws[match(task, locator$task_id)] else value(status$metric_draws))
}

for (i in seq_len(nrow(active))) {
  a <- active[i, , drop = FALSE]
  if (a$fit_metric_active) {
    engine <- if (grepl("^qdesn", a$model_variant)) "qdesn" else "dqlm"
    chains <- if (a$inference == "mcmc") 1:3 else 1L
    for (chain in chains) {
      task <- sprintf("%s__%s__c%02d", engine, a$replay_id, chain)
      config_relative <- file.path("jobs", task, "config.json")
      status_relative <- file.path("jobs", task, "status.json")
      if (all(c(config_relative, status_relative) %in% bundle_manifest$relative_path)) {
        cp <- bundle_pin(config_relative); sp <- bundle_pin(status_relative)
        add(a, "historical_fitting_metric", task, cp, sp, sha(cp), sha(sp))
      } else if (a$model_variant == "exdqlm" && a$inference == "mcmc") {
        r <- rolling[rolling$family == a$family & rolling$tau == a$tau &
          rolling$chain_id == chain, ]
        stopifnot(nrow(r) == 1L)
        add(a, "historical_fitting_metric", task, r$row_config_path,
          r$row_status_path, r$row_config_sha256)
      }
    }
  }
  if (a$forecast_metrics_active) {
    rows <- locator[locator$replay_id == a$replay_id, ]
    stopifnot(nrow(rows) == 3L, identical(sort(rows$chain_id), 1:3))
    for (j in seq_len(nrow(rows))) add(a, "forecast_reconstruction",
      rows$task_id[j], rows$contract_path[j], file.path(rows$job_root[j], "task_status.json"),
      rows$contract_sha256[j])
  }
}
receipts <- do.call(rbind, receipts)
stopifnot(all(key(receipts) %in% key(active)))
active$historical_fitting_receipts <- vapply(key(active), function(k)
  sum(key(receipts) == k & receipts$evidence_stage == "historical_fitting_metric"), integer(1))
active$forecast_reconstruction_receipts <- vapply(key(active), function(k)
  sum(key(receipts) == k & receipts$evidence_stage == "forecast_reconstruction"), integer(1))
active$fitting_evidence_gap <- active$fit_metric_active & active$historical_fitting_receipts == 0L
active$matched_vb_mcmc_timing_available <- FALSE
stopifnot(!any(active$fitting_evidence_gap), nrow(receipts) == 276L,
  sum(receipts$evidence_stage == "historical_fitting_metric") == 144L,
  sum(receipts$timing_scope == "cached_forecast_rescoring_only") == 11L,
  sum(receipts$timing_scope == "reconstructed_fit_forecast_and_export_workflow") == 121L,
  all(receipts$n_burn_requested[receipts$inference == "mcmc"] == 5000L),
  all(receipts$n_mcmc_requested[receipts$inference == "mcmc"] == 20000L),
  all(receipts$thin_requested[receipts$inference == "mcmc"] == 1L))
write.csv(active, "tables/independent_current_computation_sources_20261029.csv", row.names = FALSE, na = "")
write.csv(receipts, "tables/independent_current_computation_receipts_20261029.csv", row.names = FALSE, na = "")
inputs <- c(fit_path, forecast_path,
  "scripts/audit_independent_computation_evidence_20261029.R")
input_manifest <- data.frame(role = c("active_fitting_results", "active_forecast_results", "metadata_audit_script"),
  artifact = inputs, sha256 = vapply(inputs, sha, character(1)))
input_manifest <- rbind(input_manifest, data.frame(
  role = c("forecast_locator", "forecast_locator_manifest", "historical_bundle_manifest",
    "historical_rolling_exdqlm_job_manifest"),
  artifact = c("protected_source_locator.csv", "artifact_manifest.csv", "bundle_file_manifest.csv",
    "rolling_exdqlm/manifests/job_manifest.csv"),
  sha256 = vapply(c(locator_path, promotion_manifest_path, bundle_manifest_path,
    rolling_manifest_path), sha, character(1))))
write.csv(input_manifest, "tables/independent_current_computation_inputs_20261029.csv", row.names = FALSE, na = "")
cat("Active sources:", nrow(active), "; Q-DESN sources:", sum(grepl("^qdesn", active$model_variant)),
  "; receipts:", nrow(receipts), "; fitting-source gaps:", sum(active$fitting_evidence_gap), "\n")
print(table(receipts$evidence_stage, receipts$timing_scope))
