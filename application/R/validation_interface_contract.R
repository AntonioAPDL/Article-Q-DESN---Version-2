# Guards for future shared Q-DESN / exDQLM fit+forecast validation outputs.

app_shared_fitforecast_disallowed_tokens <- function() {
  c(
    "/home/jaguir26/local/src",
    "/data/jaguir26/local/src/exdqlm__wt__qdesn_fitforecast_0p5p0",
    "/data/jaguir26/local/src/exdqlm__wt__validation_fitforecast_0p5p0",
    "/data/jaguir26/local/src/exdqlm__wt__qdesn_0p4p0_integration",
    "/data/jaguir26/local/src/exdqlm__wt__validation_rerun_after_0p4p0_integration",
    "feature/qdesn-fitforecast-validation-0p5p0",
    "1417a825d24a6ac805b3b4af8033bb8e14a29187"
  )
}

app_fail_on_disallowed_validation_text <- function(text, context = "validation interface") {
  text <- paste(as.character(unlist(text, use.names = FALSE)), collapse = "\n")
  hits <- app_shared_fitforecast_disallowed_tokens()[
    vapply(app_shared_fitforecast_disallowed_tokens(), grepl, logical(1L), x = text, fixed = TRUE)
  ]
  if (length(hits)) {
    stop(
      sprintf(
        "%s contains stale validation source reference(s): %s",
        context,
        paste(unique(hits), collapse = "; ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_required_shared_fitforecast_interface_columns <- function() {
  c(
    "validation_contract_id", "study_id", "run_tag",
    "model_family", "model_variant", "inference", "phase", "status",
    "failure_reason", "health_gate",
    "source_registry_root", "source_registry_hash_name", "source_registry_hash_value",
    "source_cell_id", "scenario_id", "family", "tau",
    "fit_size", "effective_fit_size", "TT_warmup", "TT_main", "TT_total",
    "train_start_source_index", "train_end_source_index",
    "forecast_origin_source_index", "forecast_start_source_index",
    "forecast_end_source_index",
    "forecast_h100_start_source_index", "forecast_h100_end_source_index",
    "forecast_h100_n", "forecast_h100_q_mae", "forecast_h100_q_rmse",
    "forecast_h100_pinball_mean",
    "forecast_h1000_start_source_index", "forecast_h1000_end_source_index",
    "forecast_h1000_n", "forecast_h1000_q_mae", "forecast_h1000_q_rmse",
    "forecast_h1000_pinball_mean",
    "fit_n", "fit_q_mae", "fit_q_rmse", "fit_pinball_mean",
    "runtime_sec_total",
    "row_config_path", "row_status_path", "row_health_path", "row_metrics_path",
    "fit_path_summary_path", "forecast_path_summary_path", "log_path",
    "package_version", "branch", "commit"
  )
}

app_required_shared_fitforecast_manifest_columns <- function() {
  c(
    "study_id", "run_tag", "scenario_id", "source_cell_id",
    "family", "tau", "fit_size", "model_variant", "inference",
    "train_start_source_index", "train_end_source_index",
    "forecast_origin_source_index",
    "forecast_start_source_index", "forecast_end_source_index",
    "series_wide_path", "series_wide_sha256"
  )
}

app_validate_shared_fitforecast_interface <- function(interface,
                                                      row_manifest = NULL,
                                                      require_forecast_metric_counts = TRUE) {
  app_check_required_columns(
    interface,
    app_required_shared_fitforecast_interface_columns(),
    "shared fit+forecast interface"
  )
  app_fail_on_disallowed_validation_text(interface, "shared fit+forecast interface")

  if (isTRUE(require_forecast_metric_counts)) {
    if (any(is.na(interface$forecast_h100_n)) || any(interface$forecast_h100_n <= 0)) {
      stop("Shared fit+forecast interface must include nonmissing H=100 metric counts.", call. = FALSE)
    }
    if (any(is.na(interface$forecast_h1000_n)) || any(interface$forecast_h1000_n <= 0)) {
      stop("Shared fit+forecast interface must include nonmissing H=1000 metric counts.", call. = FALSE)
    }
  }
  hash_cols <- c("source_registry_hash_name", "source_registry_hash_value")
  if (any(!nzchar(as.character(unlist(interface[hash_cols], use.names = FALSE))))) {
    stop("Shared fit+forecast interface is missing required source registry hash fields.", call. = FALSE)
  }
  provenance_cols <- c("validation_contract_id", "package_version", "branch", "commit", "run_tag")
  if (any(!nzchar(as.character(unlist(interface[provenance_cols], use.names = FALSE))))) {
    stop("Shared fit+forecast interface is missing required validation provenance fields.", call. = FALSE)
  }
  window_cols <- c(
    "train_start_source_index", "train_end_source_index",
    "forecast_origin_source_index", "forecast_start_source_index",
    "forecast_end_source_index",
    "forecast_h100_start_source_index", "forecast_h100_end_source_index",
    "forecast_h1000_start_source_index", "forecast_h1000_end_source_index"
  )
  if (any(is.na(unlist(interface[window_cols], use.names = FALSE)))) {
    stop("Shared fit+forecast interface is missing forecast-origin/window metadata.", call. = FALSE)
  }
  if (any(interface$forecast_origin_source_index != interface$train_end_source_index)) {
    stop("Shared fit+forecast interface forecast origin must match the training window end.", call. = FALSE)
  }
  if (any(interface$forecast_start_source_index != interface$forecast_origin_source_index + 1L)) {
    stop("Shared fit+forecast interface forecast block must start immediately after the forecast origin.", call. = FALSE)
  }

  if (!is.null(row_manifest)) {
    app_check_required_columns(
      row_manifest,
      app_required_shared_fitforecast_manifest_columns(),
      "shared fit+forecast row manifest"
    )
    app_fail_on_disallowed_validation_text(row_manifest, "shared fit+forecast row manifest")
    manifest_match_cols <- c(
      "study_id", "run_tag", "scenario_id", "source_cell_id",
      "family", "tau", "fit_size", "model_variant", "inference"
    )
    key <- do.call(paste, c(interface[manifest_match_cols], sep = "\r"))
    manifest_key <- do.call(paste, c(row_manifest[manifest_match_cols], sep = "\r"))
    missing_key <- setdiff(unique(key), unique(manifest_key))
    if (length(missing_key)) {
      stop("Shared fit+forecast interface row(s) are missing from the row manifest.", call. = FALSE)
    }
    windows <- row_manifest[match(key, manifest_key), , drop = FALSE]
    if (any(is.na(windows$train_start_source_index)) ||
        any(is.na(windows$train_end_source_index)) ||
        any(is.na(windows$forecast_origin_source_index)) ||
        any(is.na(windows$forecast_start_source_index)) ||
        any(is.na(windows$forecast_end_source_index))) {
      stop("Shared fit+forecast row manifest is missing forecast-origin/window metadata.", call. = FALSE)
    }
  }

  invisible(TRUE)
}

app_default_tt500_final_validation_config <- function() {
  app_path("application/config/shared_validation_tt500_final_fitforecast.yaml")
}

app_required_tt500_final_config_fields <- function() {
  c(
    "artifact_id", "artifact_status", "article_consumable", "is_final",
    "validation_worktree", "validation_branch",
    "validation_head_commit_at_article_sync", "package_version",
    "source_registry_root", "source_registry_hash_name",
    "source_registry_hash_value", "fit_size",
    "train_start_source_index", "train_end_source_index",
    "forecast_origin_source_index", "forecast_block_start_source_index",
    "forecast_block_end_source_index", "max_lead_configured",
    "origin_stride", "forecast_protocol", "interfaces",
    "article_outputs", "article_policy"
  )
}

app_required_tt500_final_interface_columns <- function() {
  c(
    "validation_contract_id", "interface_schema_version", "study_id",
    "run_tag", "spec_id", "model_family", "model_variant",
    "inference", "inference_method", "status", "health_gate",
    "signoff_grade", "source_registry_root", "source_registry_path",
    "source_registry_hash_name", "source_registry_hash_value",
    "source_registry_hash", "source_cell_id", "scenario_id",
    "source_path", "source_hash", "true_quantile_path",
    "true_quantile_hash", "family", "tau", "fit_size",
    "effective_fit_size", "TT_warmup", "TT_main", "TT_total",
    "train_start_source_index", "train_end_source_index",
    "forecast_protocol", "state_update_method", "refit_per_origin",
    "max_lead_configured", "origin_stride",
    "forecast_origin_source_index", "forecast_block_start_source_index",
    "forecast_block_end_source_index", "rolling_origin_start_source_index",
    "rolling_origin_end_source_index", "forecast_lead",
    "target_start_source_index", "target_end_source_index",
    "n_origins_scored", "fit_qtrue_mae", "fit_qtrue_rmse",
    "fit_pinball_mean", "forecast_qtrue_mae", "forecast_qtrue_rmse",
    "forecast_pinball_mean", "runtime_sec_fit",
    "runtime_sec_forecast", "runtime_sec_total",
    "forecast_lead_metrics_path", "storage_policy",
    "artifact_manifest_path", "artifact_manifest_hash",
    "compact_path_summary_path", "compact_path_summary_hash",
    "log_path", "config_path", "config_hash", "package_version",
    "validation_branch", "validation_commit"
  )
}

app_tt500_final_interface_names <- function(config) {
  names(config$interfaces %||% list())
}

app_nonempty_unique <- function(x) {
  x <- unique(as.character(x))
  x[nzchar(x) & !is.na(x)]
}

app_check_all_equal <- function(x, expected, label) {
  raw <- as.character(x)
  if (any(is.na(raw) | !nzchar(raw))) {
    stop(sprintf("%s contains missing values.", label), call. = FALSE)
  }
  observed <- app_nonempty_unique(raw)
  if (!length(observed) || any(!observed %in% as.character(expected))) {
    stop(
      sprintf(
        "%s mismatch; expected %s, observed %s.",
        label,
        paste(as.character(expected), collapse = ", "),
        paste(observed, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_validate_tt500_final_lead_grid <- function(interface, label, max_lead) {
  lead_key_cols <- c("spec_id", "fit_size")
  key <- do.call(paste, c(interface[lead_key_cols], sep = "\r"))
  bad <- character()
  for (kk in unique(key)) {
    rows <- interface[key == kk, , drop = FALSE]
    leads <- sort(unique(as.integer(rows$forecast_lead)))
    if (!identical(leads, seq_len(as.integer(max_lead)))) {
      bad <- c(bad, rows$spec_id[[1L]])
    }
  }
  if (length(bad)) {
    stop(
      sprintf(
        "%s is missing the complete rolling-origin lead grid for spec(s): %s",
        label,
        paste(utils::head(unique(bad), 5L), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_validate_tt500_final_one_interface <- function(config, interface_id, spec) {
  label <- sprintf("TT500 final interface '%s'", interface_id)
  required_spec <- c(
    "model_family", "interface_role", "path", "sha256",
    "validation_commit_at_export", "expected_rows_total",
    "expected_rows_tt500", "expected_fit_size_values",
    "expected_inference_values", "accepted_status_values",
    "require_scale_repaired_qdesn_forecasts"
  )
  missing_spec <- setdiff(required_spec, names(spec))
  if (length(missing_spec)) {
    stop(
      sprintf("%s config is missing required field(s): %s", label, paste(missing_spec, collapse = ", ")),
      call. = FALSE
    )
  }
  app_fail_on_disallowed_validation_text(spec, label)
  if (!file.exists(spec$path)) {
    stop(sprintf("%s file does not exist: %s", label, spec$path), call. = FALSE)
  }
  observed_hash <- app_sha256_file(spec$path)
  if (!identical(observed_hash, as.character(spec$sha256))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }

  interface <- app_read_csv(spec$path)
  app_check_required_columns(
    interface,
    app_required_tt500_final_interface_columns(),
    label
  )
  app_fail_on_disallowed_validation_text(interface, label)

  if (nrow(interface) != as.integer(spec$expected_rows_total)) {
    stop(sprintf("%s total row count mismatch.", label), call. = FALSE)
  }

  app_check_all_equal(interface$model_family, spec$model_family, sprintf("%s model_family", label))
  app_check_all_equal(interface$package_version, config$package_version, sprintf("%s package_version", label))
  app_check_all_equal(interface$validation_branch, config$validation_branch, sprintf("%s validation_branch", label))
  app_check_all_equal(
    interface$validation_commit,
    spec$validation_commit_at_export,
    sprintf("%s validation_commit", label)
  )
  app_check_all_equal(
    interface$source_registry_hash_value,
    config$source_registry_hash_value,
    sprintf("%s source_registry_hash_value", label)
  )
  app_check_all_equal(interface$status, spec$accepted_status_values, sprintf("%s status", label))

  observed_fit_sizes <- sort(unique(as.integer(interface$fit_size)))
  expected_fit_sizes <- sort(as.integer(unlist(spec$expected_fit_size_values, use.names = FALSE)))
  if (!identical(observed_fit_sizes, expected_fit_sizes)) {
    stop(sprintf("%s fit_size values mismatch.", label), call. = FALSE)
  }
  observed_inference <- sort(unique(as.character(interface$inference)))
  expected_inference <- sort(as.character(unlist(spec$expected_inference_values, use.names = FALSE)))
  if (!identical(observed_inference, expected_inference)) {
    stop(sprintf("%s inference values mismatch.", label), call. = FALSE)
  }

  tt500 <- interface[as.integer(interface$fit_size) == as.integer(config$fit_size), , drop = FALSE]
  if (nrow(tt500) != as.integer(spec$expected_rows_tt500)) {
    stop(sprintf("%s TT500 row count mismatch.", label), call. = FALSE)
  }
  window_checks <- list(
    train_start_source_index = config$train_start_source_index,
    train_end_source_index = config$train_end_source_index,
    forecast_origin_source_index = config$forecast_origin_source_index,
    forecast_block_start_source_index = config$forecast_block_start_source_index,
    forecast_block_end_source_index = config$forecast_block_end_source_index,
    max_lead_configured = config$max_lead_configured,
    origin_stride = config$origin_stride,
    forecast_protocol = config$forecast_protocol
  )
  for (nm in names(window_checks)) {
    app_check_all_equal(tt500[[nm]], window_checks[[nm]], sprintf("%s %s", label, nm))
  }
  app_validate_tt500_final_lead_grid(tt500, label, config$max_lead_configured)

  metric_cols <- c(
    "fit_qtrue_rmse", "fit_pinball_mean",
    "forecast_qtrue_mae", "forecast_qtrue_rmse", "forecast_pinball_mean",
    "runtime_sec_total", "n_origins_scored"
  )
  if (any(!is.finite(as.numeric(unlist(tt500[metric_cols], use.names = FALSE))))) {
    stop(sprintf("%s contains nonfinite TT500 metric fields.", label), call. = FALSE)
  }
  if (isTRUE(spec$require_scale_repaired_qdesn_forecasts)) {
    if (any(!grepl("scale_repaired", as.character(tt500$forecast_lead_metrics_path), fixed = TRUE))) {
      stop(sprintf("%s is missing scale-repaired Q-DESN forecast metric paths.", label), call. = FALSE)
    }
  }

  tt500$article_interface_id <- interface_id
  tt500$article_interface_role <- as.character(spec$interface_role)
  tt500$article_interface_sha256 <- observed_hash
  list(interface = interface, tt500 = tt500, sha256 = observed_hash)
}

app_validate_tt500_final_validation <- function(
    config_path = app_default_tt500_final_validation_config()) {
  config <- app_read_yaml(config_path)
  missing_config <- setdiff(app_required_tt500_final_config_fields(), names(config))
  if (length(missing_config)) {
    stop(
      sprintf(
        "TT500 final validation config is missing required field(s): %s",
        paste(missing_config, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  app_fail_on_disallowed_validation_text(config, "TT500 final validation config")
  if (!identical(config$artifact_status, "final_article_facing_tt500")) {
    stop("TT500 final validation config must be marked final_article_facing_tt500.", call. = FALSE)
  }
  if (!isTRUE(config$article_consumable) || !isTRUE(config$is_final)) {
    stop("TT500 final validation config must be final and article-consumable.", call. = FALSE)
  }
  if (identical(app_tt500_final_interface_names(config), character(0))) {
    stop("TT500 final validation config does not declare any interfaces.", call. = FALSE)
  }

  checked <- lapply(app_tt500_final_interface_names(config), function(interface_id) {
    app_validate_tt500_final_one_interface(config, interface_id, config$interfaces[[interface_id]])
  })
  names(checked) <- app_tt500_final_interface_names(config)
  tt500 <- do.call(rbind, lapply(checked, `[[`, "tt500"))
  rownames(tt500) <- NULL

  expected_rows <- sum(vapply(config$interfaces, function(x) as.integer(x$expected_rows_tt500), integer(1L)))
  if (nrow(tt500) != expected_rows) {
    stop("Combined TT500 final interface row count mismatch.", call. = FALSE)
  }

  list(config = config, checked = checked, tt500 = tt500)
}

app_default_tt500_provisional_progress_config <- function() {
  app_path("application/config/shared_validation_tt500_provisional_progress.yaml")
}

app_required_tt500_provisional_config_fields <- function() {
  c(
    "artifact_id", "artifact_status", "article_consumable", "is_final",
    "validation_worktree", "validation_branch", "validation_commit_at_export",
    "package_version", "run_tag", "campaign_id",
    "source_registry_root", "source_registry_hash_name", "source_registry_hash_value",
    "provisional_progress_dir", "atomic_progress_path", "atomic_progress_sha256",
    "root_progress_path", "root_progress_sha256", "manifest_path", "manifest_sha256",
    "expected_counts", "refresh_command", "article_policy"
  )
}

app_required_tt500_provisional_atomic_columns <- function() {
  c(
    "provisional_table_version", "provisional_generated_at",
    "is_final", "article_consumable", "article_consumption_policy",
    "run_tag", "campaign_id", "spec_id", "root_id", "dataset_cell_id",
    "model_family", "model_variant", "family", "tau", "fit_size",
    "effective_fit_size", "prior", "method", "inference", "likelihood_family",
    "status", "completion_state", "placeholder_reason", "metrics_available",
    "fit_summary_present", "forecast_horizon_summary_present",
    "TT_warmup", "TT_main", "TT_total",
    "train_start_source_index", "train_end_source_index",
    "forecast_origin_source_index", "forecast_start_source_index",
    "forecast_end_source_index", "max_lead_configured", "origin_stride",
    "source_registry_root", "source_registry_hash_name", "source_registry_hash_value",
    "fit_summary_path", "forecast_horizon_summary_path",
    "validation_repo", "validation_branch", "validation_commit", "package_version"
  )
}

app_required_tt500_provisional_root_columns <- function() {
  c(
    "provisional_table_version", "provisional_generated_at",
    "is_final", "article_consumable", "run_tag", "campaign_id",
    "root_id", "dataset_cell_id", "family", "tau", "fit_size", "prior",
    "atomic_specs_total", "atomic_specs_complete", "atomic_specs_running",
    "atomic_specs_pending", "root_completion_state",
    "exal_state", "exal_status", "al_state", "al_status"
  )
}

app_falseish_vec <- function(x) {
  if (is.logical(x)) return(!is.na(x) & !x)
  tolower(as.character(x)) %in% c("false", "f", "0", "no", "n")
}

app_validate_tt500_provisional_progress <- function(
    config_path = app_default_tt500_provisional_progress_config(),
    require_hashes = TRUE) {
  config <- app_read_yaml(config_path)
  missing_config <- setdiff(app_required_tt500_provisional_config_fields(), names(config))
  if (length(missing_config)) {
    stop(
      sprintf(
        "TT500 provisional progress config is missing required field(s): %s",
        paste(missing_config, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  app_fail_on_disallowed_validation_text(config, "TT500 provisional progress config")

  if (!identical(config$artifact_status, "provisional_progress_only")) {
    stop("TT500 progress config must be marked provisional_progress_only.", call. = FALSE)
  }
  if (!isFALSE(config$article_consumable) || !isFALSE(config$is_final)) {
    stop("TT500 provisional progress config must remain non-final and non-article-consumable.", call. = FALSE)
  }

  atomic <- app_read_csv(config$atomic_progress_path)
  root <- app_read_csv(config$root_progress_path)
  app_check_required_columns(
    atomic,
    app_required_tt500_provisional_atomic_columns(),
    "TT500 provisional atomic progress table"
  )
  app_check_required_columns(
    root,
    app_required_tt500_provisional_root_columns(),
    "TT500 provisional root progress table"
  )
  app_fail_on_disallowed_validation_text(atomic, "TT500 provisional atomic progress table")
  app_fail_on_disallowed_validation_text(root, "TT500 provisional root progress table")

  if (!all(app_falseish_vec(atomic$is_final)) ||
      !all(app_falseish_vec(atomic$article_consumable)) ||
      !all(app_falseish_vec(root$is_final)) ||
      !all(app_falseish_vec(root$article_consumable))) {
    stop("TT500 provisional progress rows must remain non-final and non-article-consumable.", call. = FALSE)
  }
  if (any(!nzchar(as.character(atomic$source_registry_hash_value)))) {
    stop("TT500 provisional progress table is missing source registry hash values.", call. = FALSE)
  }
  if (any(is.na(atomic$forecast_origin_source_index)) ||
      any(is.na(atomic$train_start_source_index)) ||
      any(is.na(atomic$train_end_source_index)) ||
      any(is.na(atomic$forecast_start_source_index)) ||
      any(is.na(atomic$forecast_end_source_index))) {
    stop("TT500 provisional progress table is missing source-window metadata.", call. = FALSE)
  }
  if (any(is.na(atomic$max_lead_configured)) || any(is.na(atomic$origin_stride))) {
    stop("TT500 provisional progress table is missing rolling-origin lead/stride metadata.", call. = FALSE)
  }

  expected <- config$expected_counts
  if (!is.null(expected$atomic_specs_total) && nrow(atomic) != as.integer(expected$atomic_specs_total)) {
    stop("TT500 provisional atomic progress row count does not match config.", call. = FALSE)
  }
  if (!is.null(expected$root_specs_total) && nrow(root) != as.integer(expected$root_specs_total)) {
    stop("TT500 provisional root progress row count does not match config.", call. = FALSE)
  }
  check_count <- function(name, observed) {
    if (!is.null(expected[[name]]) && observed != as.integer(expected[[name]])) {
      stop(sprintf("TT500 provisional count '%s' does not match config.", name), call. = FALSE)
    }
  }
  check_count("atomic_specs_complete", sum(atomic$completion_state == "complete", na.rm = TRUE))
  check_count("atomic_specs_running", sum(atomic$completion_state == "running", na.rm = TRUE))
  check_count("atomic_specs_pending", sum(atomic$completion_state == "pending", na.rm = TRUE))
  check_count("root_specs_complete", sum(root$root_completion_state == "complete", na.rm = TRUE))
  check_count("root_specs_running", sum(root$root_completion_state == "running", na.rm = TRUE))

  if (isTRUE(require_hashes)) {
    hash_checks <- c(
      atomic_progress_sha256 = config$atomic_progress_path,
      root_progress_sha256 = config$root_progress_path,
      manifest_sha256 = config$manifest_path
    )
    for (nm in names(hash_checks)) {
      expected_hash <- as.character(config[[nm]])
      observed_hash <- app_sha256_file(hash_checks[[nm]])
      if (!identical(observed_hash, expected_hash)) {
        stop(sprintf("TT500 provisional artifact hash mismatch for %s.", nm), call. = FALSE)
      }
    }
  }

  app_require_namespace("jsonlite")
  manifest <- jsonlite::read_json(config$manifest_path, simplifyVector = TRUE)
  if (!isFALSE(manifest$article_consumable) || !isFALSE(manifest$is_final)) {
    stop("TT500 provisional manifest must remain non-final and non-article-consumable.", call. = FALSE)
  }
  if (!identical(as.character(manifest$source_registry_hash_value), as.character(config$source_registry_hash_value))) {
    stop("TT500 provisional manifest source hash does not match Article config.", call. = FALSE)
  }
  if (!identical(as.character(manifest$validation_branch), as.character(config$validation_branch))) {
    stop("TT500 provisional manifest branch does not match Article config.", call. = FALSE)
  }
  if (!identical(as.character(manifest$validation_commit), as.character(config$validation_commit_at_export))) {
    stop("TT500 provisional manifest commit does not match Article config.", call. = FALSE)
  }

  invisible(list(config = config, atomic = atomic, root = root, manifest = manifest))
}
