#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))

args <- app_parse_args(list(
  shortlist = "application/config/glofas_fit_recovery_distributional_shortlist_20260731.csv",
  source_recovery_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_triage_20260731",
  quantiles = "0.05,0.95",
  cutoff_date = "2022-12-25"
))

resolve_repo <- function(path, must_work = FALSE) {
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

resolve_recorded_path <- function(path) {
  path <- as.character(path)
  if (grepl("^/", path)) normalizePath(path, mustWork = TRUE) else normalizePath(app_path(path), mustWork = TRUE)
}

read_single_qdesn_manifest_row <- function(run_dir, quantile_level) {
  path <- file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv")
  x <- app_read_csv(path)
  x <- x[
    abs(as.numeric(x$quantile_level) - quantile_level) < 1e-12 &
      as.character(x$status) == "completed",
    , drop = FALSE
  ]
  if (nrow(x) != 1L) stop(sprintf("Expected one completed p50 fit manifest row in %s.", run_dir), call. = FALSE)
  x
}

validate_source_p50 <- function(candidate_id, source_row) {
  run_dir <- resolve_recorded_path(source_row$run_dir[[1L]])
  marker <- file.path(run_dir, ".fit_recovery_complete")
  history_path <- file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv")
  diagnostics_path <- file.path(run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  if (!file.exists(marker) || !file.exists(history_path) || !file.exists(diagnostics_path)) {
    stop(sprintf("The p50 source is incomplete for %s.", candidate_id), call. = FALSE)
  }
  fit_manifest <- read_single_qdesn_manifest_row(run_dir, 0.5)
  fit_object <- resolve_recorded_path(fit_manifest$fit_object[[1L]])
  diagnostics <- app_read_csv(diagnostics_path)
  diagnostics <- diagnostics[abs(as.numeric(diagnostics$quantile_level) - 0.5) < 1e-12, , drop = FALSE]
  if (nrow(diagnostics) != 1L ||
      !isTRUE(app_as_bool_vec(diagnostics$vb_converged)[[1L]]) ||
      !isTRUE(app_as_bool_vec(diagnostics$finite_theta)[[1L]]) ||
      !isTRUE(app_as_bool_vec(diagnostics$finite_sigma)[[1L]])) {
    stop(sprintf("The p50 source failed convergence/finite-state gates for %s.", candidate_id), call. = FALSE)
  }
  fit_payload <- readRDS(fit_object)
  fit <- fit_payload$fit %||% fit_payload
  theta_mean <- fit$variational_state$theta_mean %||% fit$summary$theta_mean %||% NULL
  theta_cov <- fit$variational_state$theta_cov %||% fit$summary$theta_cov %||% NULL
  expected_theta <- as.integer(diagnostics$n_theta[[1L]])
  if (is.null(theta_mean) || length(theta_mean) != expected_theta ||
      is.null(theta_cov) || !identical(dim(as.matrix(theta_cov)), c(expected_theta, expected_theta))) {
    stop(sprintf("The p50 warm-start coefficient state is dimensionally invalid for %s.", candidate_id), call. = FALSE)
  }
  list(
    run_dir = run_dir,
    history_path = normalizePath(history_path, mustWork = TRUE),
    fit_object = fit_object,
    fit_object_sha256 = app_sha256_file(fit_object),
    fit_manifest = fit_manifest,
    diagnostics = diagnostics,
    n_theta = expected_theta
  )
}

quantiles <- as.numeric(trimws(strsplit(as.character(args$quantiles), ",", fixed = TRUE)[[1L]]))
if (length(quantiles) != 2L || !isTRUE(all.equal(sort(quantiles), c(0.05, 0.95), tolerance = 1e-12))) {
  stop("Stage A requires exactly the p05 and p95 missing quantiles.", call. = FALSE)
}
cutoff_date <- as.Date(args$cutoff_date)
if (is.na(cutoff_date)) stop("A valid cutoff date is required.", call. = FALSE)

shortlist_path <- resolve_repo(args$shortlist, must_work = TRUE)
source_root <- resolve_repo(args$source_recovery_root, must_work = TRUE)
output_root <- resolve_repo(args$output_root, must_work = FALSE)
shortlist <- app_glofas_selection_validate_shortlist(app_read_csv(shortlist_path))
source_runtime <- app_read_csv(file.path(source_root, "runtime_manifest.csv"))
if (!all(shortlist$candidate_id %in% source_runtime$candidate_id)) {
  stop("One or more shortlisted candidates are absent from the p50 recovery manifest.", call. = FALSE)
}

for (dir in c("candidates", "common_cache", "runs", "logs", "generated", "scores", "status", "tables", "figures", "cleanup")) {
  app_ensure_dir(file.path(output_root, dir))
}
source_panel <- file.path(source_root, "common_cache", "application_panel.rds")
target_panel <- file.path(output_root, "common_cache", "application_panel.rds")
if (!file.exists(source_panel)) stop("The audited p50 application panel is missing.", call. = FALSE)
if (!file.exists(target_panel) && !file.copy(source_panel, target_panel, copy.mode = TRUE, copy.date = TRUE)) {
  stop("Could not copy the audited p50 application panel into the Stage A cache.", call. = FALSE)
}
if (!identical(app_sha256_file(source_panel), app_sha256_file(target_panel))) {
  stop("The Stage A application-panel copy failed its hash check.", call. = FALSE)
}

runtime_rows <- list()
source_rows <- list()
priority <- 0L
for (i in seq_len(nrow(shortlist))) {
  candidate <- shortlist[i, , drop = FALSE]
  candidate_id <- candidate$candidate_id[[1L]]
  source_row <- source_runtime[source_runtime$candidate_id == candidate_id, , drop = FALSE]
  if (nrow(source_row) != 1L) stop(sprintf("Ambiguous p50 runtime row for %s.", candidate_id), call. = FALSE)
  p50 <- validate_source_p50(candidate_id, source_row)
  source_config_path <- resolve_recorded_path(source_row$config_path[[1L]])
  source_model_grid_path <- resolve_recorded_path(source_row$model_grid_path[[1L]])
  source_config <- app_read_config(source_config_path)
  source_model_grid <- app_read_csv(source_model_grid_path)
  covariate_policy <- app_validate_covariate_source_policy(
    source_config,
    cutoff_row = data.frame(origin_date = cutoff_date),
    stop_on_failure = FALSE
  )
  if (!identical(covariate_policy$status[[1L]], "PASS")) {
    stop(sprintf(
      "Candidate %s failed its inherited covariate-policy gate: %s",
      candidate_id, covariate_policy$message[[1L]]
    ), call. = FALSE)
  }
  source_rows[[length(source_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    role = candidate$role[[1L]],
    quantile_id = "p50",
    quantile_level = 0.5,
    source_kind = "reused_p50",
    run_id = source_row$run_id[[1L]],
    run_dir = p50$run_dir,
    config_path = source_config_path,
    config_sha256 = app_sha256_file(source_config_path),
    model_grid_path = source_model_grid_path,
    model_grid_sha256 = app_sha256_file(source_model_grid_path),
    history_path = p50$history_path,
    fit_object = p50$fit_object,
    fit_object_sha256 = p50$fit_object_sha256,
    warm_start_source_fit_object = NA_character_,
    warm_start_source_sha256 = NA_character_,
    expected_n_theta = p50$n_theta,
    covariate_future_policy = covariate_policy$future_policy[[1L]],
    covariate_source_provider = covariate_policy$source_provider[[1L]],
    covariate_uses_realized_future = covariate_policy$uses_realized_future[[1L]],
    covariate_deployable = covariate_policy$deployable_forecast_covariates[[1L]],
    status = "completed_source",
    stringsAsFactors = FALSE
  )

  for (quantile_level in quantiles) {
    priority <- priority + 1L
    quantile_id <- app_glofas_selection_quantile_id(quantile_level)
    worker_id <- paste(candidate_id, quantile_id, sep = "__")
    candidate_root <- file.path(output_root, "candidates", candidate_id, quantile_id)
    app_ensure_dir(candidate_root)
    quantile_grid_path <- file.path(candidate_root, paste0("quantile_grid_", quantile_id, ".csv"))
    app_write_csv(data.frame(
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      role = if (quantile_level < 0.5) "lower_tail" else "upper_tail",
      enabled = TRUE,
      stringsAsFactors = FALSE
    ), quantile_grid_path)

    fit_id <- paste0("qdesn_fit_recovery_triage_", candidate_id, "_", quantile_id)
    raw_fit_id <- paste0("raw_glofas_fit_recovery_triage_", candidate_id, "_", quantile_id)
    model_grid <- source_model_grid
    raw_row <- model_grid$model_family == "raw_glofas"
    qdesn_row <- model_grid$model_family == "qdesn_glofas_discrepancy"
    if (sum(raw_row) != 1L || sum(qdesn_row) != 1L) {
      stop(sprintf("Source model grid is not a one-pair grid for %s.", candidate_id), call. = FALSE)
    }
    model_grid$fit_id[raw_row] <- raw_fit_id
    model_grid$model_id[raw_row] <- raw_fit_id
    model_grid$fit_id[qdesn_row] <- fit_id
    model_grid$model_id[qdesn_row] <- fit_id
    model_grid$quantile_level <- quantile_level
    model_grid$notes[raw_row] <- paste("Raw GloFAS", quantile_id, "baseline for", candidate_id)
    model_grid$notes[qdesn_row] <- paste("Independent Stage A", quantile_id, "fit for", candidate_id)
    model_grid_path <- file.path(candidate_root, paste0("model_grid_", quantile_id, ".csv"))
    app_write_csv(model_grid, model_grid_path)

    cfg <- source_config
    cfg$.__config_path__ <- NULL
    cfg$application_name <- paste0("glofas_fit_recovery_triage_", candidate_id, "_", quantile_id)
    cfg$description <- paste(
      "Independent", quantile_id, "Stage A fit for historical-fit recovery candidate", candidate_id
    )
    cfg$paths$model_grid <- model_grid_path
    cfg$paths$quantile_grid <- quantile_grid_path
    cfg$paths$cache <- file.path(output_root, "common_cache")
    cfg$paths$runs <- file.path(output_root, "runs")
    cfg$paths$logs <- file.path(output_root, "logs")
    cfg$paths$generated_outputs <- file.path(output_root, "generated")
    cfg$inference$vb_ld$warm_start <- list(
      enabled = TRUE,
      fit_object = p50$fit_object,
      use_theta = TRUE,
      use_future = FALSE,
      use_sigma = FALSE,
      require_theta = TRUE,
      require_future = FALSE,
      require_sigma = FALSE,
      covariance_jitter = 1.0e-8
    )
    cfg$post_analysis$run_after_outputs <- TRUE
    cfg$post_analysis$recent_history_n <- 200L
    cfg$post_analysis$storage$write_history_draws_rds <- FALSE
    cfg$post_analysis$storage$write_history_draws_csv <- FALSE
    cfg$execution$artifacts <- list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      retain_prediction_design_object = TRUE,
      retain_reference_fit_object = TRUE
    )
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- paste(
      "Explicit Stage A tail fit; independent objective with coefficient-only p50 initialization for", worker_id
    )
    config_path <- file.path(candidate_root, paste0("config_", quantile_id, ".yaml"))
    app_write_yaml(cfg, config_path)

    run_id <- paste0("glofas_fit_recovery_triage_20260731_", candidate_id, "_", quantile_id)
    run_dir <- file.path(output_root, "runs", run_id)
    fit_object <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
    history_path <- file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv")
    runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
      candidate_id = worker_id,
      base_candidate_id = candidate_id,
      role = candidate$role[[1L]],
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
      warm_start_source_fit_object = p50$fit_object,
      warm_start_source_sha256 = p50$fit_object_sha256,
      expected_n_theta = p50$n_theta,
      covariate_future_policy = covariate_policy$future_policy[[1L]],
      covariate_source_provider = covariate_policy$source_provider[[1L]],
      covariate_uses_realized_future = covariate_policy$uses_realized_future[[1L]],
      covariate_deployable = covariate_policy$deployable_forecast_covariates[[1L]],
      retain_heavy = TRUE,
      status = "prepared",
      stringsAsFactors = FALSE
    )
    source_rows[[length(source_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      role = candidate$role[[1L]],
      quantile_id = quantile_id,
      quantile_level = quantile_level,
      source_kind = "new_tail_fit",
      run_id = run_id,
      run_dir = run_dir,
      config_path = config_path,
      config_sha256 = app_sha256_file(config_path),
      model_grid_path = model_grid_path,
      model_grid_sha256 = app_sha256_file(model_grid_path),
      history_path = history_path,
      fit_object = fit_object,
      fit_object_sha256 = NA_character_,
      warm_start_source_fit_object = p50$fit_object,
      warm_start_source_sha256 = p50$fit_object_sha256,
      expected_n_theta = p50$n_theta,
      covariate_future_policy = covariate_policy$future_policy[[1L]],
      covariate_source_provider = covariate_policy$source_provider[[1L]],
      covariate_uses_realized_future = covariate_policy$uses_realized_future[[1L]],
      covariate_deployable = covariate_policy$deployable_forecast_covariates[[1L]],
      status = "prepared",
      stringsAsFactors = FALSE
    )
  }
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
source_manifest <- app_bind_rows_fill(source_rows)
source_manifest <- source_manifest[order(source_manifest$candidate_id, source_manifest$quantile_level), , drop = FALSE]
source_manifest <- app_glofas_selection_validate_source_manifest(source_manifest, require_complete = FALSE)

runtime_manifest_path <- file.path(output_root, "runtime_manifest.csv")
source_manifest_path <- file.path(output_root, "quantile_source_manifest_prepared.csv")
app_write_csv(runtime_manifest, runtime_manifest_path)
app_write_csv(source_manifest, source_manifest_path)
app_write_csv(shortlist, file.path(output_root, "shortlist_snapshot.csv"))
policy_audit_path <- file.path(output_root, "tables", "covariate_policy_audit.csv")
policy_audit <- unique(source_manifest[, c(
  "candidate_id", "covariate_future_policy", "covariate_source_provider",
  "covariate_uses_realized_future", "covariate_deployable"
), drop = FALSE])
app_write_csv(policy_audit, policy_audit_path)

provenance <- data.frame(
  field = c(
    "prepared_at", "article_repo", "article_branch", "article_head", "origin_main",
    "shortlist_path", "shortlist_sha256", "source_recovery_root",
    "source_runtime_manifest_sha256", "source_panel_sha256",
    "covariate_policy_audit_sha256", "cutoff_date", "scientific_gate"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    repo_root,
    system2("git", c("-C", repo_root, "rev-parse", "--abbrev-ref", "HEAD"), stdout = TRUE)[[1L]],
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    system2("git", c("-C", repo_root, "rev-parse", "origin/main"), stdout = TRUE)[[1L]],
    shortlist_path,
    app_sha256_file(shortlist_path),
    source_root,
    app_sha256_file(file.path(source_root, "runtime_manifest.csv")),
    app_sha256_file(target_panel),
    app_sha256_file(policy_audit_path),
    as.character(cutoff_date),
    "Stage A only; no blocked-validation or full-seven successor is auto-launched"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "provenance.csv"))

launch_command <- paste(
  "python3 application/scripts/glofas_fit_recovery_scheduler.py",
  "--manifest", shQuote(runtime_manifest_path),
  "--output-root", shQuote(output_root),
  "--max-parallel 8 --max-load 58 --min-memory-gb 96 --min-disk-gb 250",
  "--poll-seconds 60 --cores 3,7,11,15,19,23,27,31"
)
writeLines(c(
  "Stage A p05/p95 triage launch",
  "",
  "The eight fits are independent quantile objectives. Their only reused numerical state is",
  "the matching p50 coefficient mean/covariance, whose hash is recorded in the source manifest.",
  "Future-path and sigma states are not reused.",
  "The inherited covariate policy is recorded explicitly; Stage A is in-sample triage, not deployable validation.",
  "",
  launch_command
), file.path(output_root, "README.txt"))

cat(runtime_manifest_path, "\n")
cat(source_manifest_path, "\n")
