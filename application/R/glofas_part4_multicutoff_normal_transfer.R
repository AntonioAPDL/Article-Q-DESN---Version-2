# Reproducible alternate-cutoff Normal Ridge/RHS transfer experiments.

app_glofas_multicutoff_required_files <- function() {
  c(
    reference_history = "reference/reference_gauge_history.csv",
    reference_scoring = "evaluation/reference_gauge_scoring_only_30d.csv",
    retrospective = "glofas/glofas_retrospective.csv",
    ensemble = "glofas/glofas_ensemble.csv",
    covariate_history = "covariates/ppt_soil_history.csv",
    covariate_future = "covariates/ppt_soil_oracle_future_30d.csv",
    contract = "metadata/bundle_contract.csv"
  )
}

app_glofas_multicutoff_bundle_paths <- function(bundle_root) {
  root <- normalizePath(bundle_root, mustWork = TRUE)
  relative <- app_glofas_multicutoff_required_files()
  paths <- setNames(file.path(root, relative), names(relative))
  missing <- names(paths)[!file.exists(paths)]
  if (length(missing)) {
    stop(
      sprintf("Alternate-cutoff bundle is missing: %s.", paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
  paths
}

app_glofas_multicutoff_forbidden_columns <- function(x) {
  grep(
    "(^|_)(nws|gefs|blend|gdpc|pca|pc1|eli|oni)($|_)",
    tolower(names(x)),
    value = TRUE
  )
}

app_glofas_multicutoff_validate_bundle <- function(bundle_root, cutoff_date) {
  paths <- app_glofas_multicutoff_bundle_paths(bundle_root)
  cutoff <- as.Date(cutoff_date)
  if (length(cutoff) != 1L || is.na(cutoff)) stop("cutoff_date must be one valid date.", call. = FALSE)
  contract <- app_read_csv(paths[["contract"]])
  if (nrow(contract) != 1L || !identical(as.Date(contract$cutoff_date[[1L]]), cutoff)) {
    stop("Bundle contract cutoff does not match the requested cutoff.", call. = FALSE)
  }
  expected_dates <- cutoff + seq_len(30L)
  expected_issued_dates <- cutoff + seq_len(28L)
  checks <- list()
  add_check <- function(name, ok, detail) {
    checks[[length(checks) + 1L]] <<- data.frame(
      check = name,
      status = if (isTRUE(ok)) "pass" else "fail",
      detail = as.character(detail),
      stringsAsFactors = FALSE
    )
  }

  reference_history <- app_read_csv(paths[["reference_history"]])
  reference_scoring <- app_read_csv(paths[["reference_scoring"]])
  retrospective <- app_read_csv(paths[["retrospective"]])
  ensemble <- app_read_csv(paths[["ensemble"]])
  covariate_history <- app_read_csv(paths[["covariate_history"]])
  covariate_future <- app_read_csv(paths[["covariate_future"]])
  app_check_required_columns(reference_history, c("date", "station_id", "streamflow"), "reference history")
  app_check_required_columns(reference_scoring, c("date", "station_id", "streamflow"), "reference scoring")
  app_check_required_columns(retrospective, c("date", "location_id", "glofas_streamflow"), "GloFAS retrospective")
  app_check_required_columns(ensemble, c("origin_date", "target_date", "horizon", "member", "glofas_streamflow"), "GloFAS ensemble")
  app_check_required_columns(covariate_history, c("date", "ppt", "soil"), "covariate history")
  app_check_required_columns(covariate_future, c("date", "ppt", "soil"), "covariate future")

  reference_history$date <- as.Date(reference_history$date)
  reference_scoring$date <- as.Date(reference_scoring$date)
  retrospective$date <- as.Date(retrospective$date)
  ensemble$origin_date <- as.Date(ensemble$origin_date)
  ensemble$target_date <- as.Date(ensemble$target_date)
  ensemble$horizon <- as.integer(ensemble$horizon)
  covariate_history$date <- as.Date(covariate_history$date)
  covariate_future$date <- as.Date(covariate_future$date)

  add_check("reference_history_ends_at_cutoff", max(reference_history$date) == cutoff, max(reference_history$date))
  add_check("reference_scoring_is_next_30_days", identical(reference_scoring$date, expected_dates), paste(range(reference_scoring$date), collapse = ":"))
  add_check("retrospective_ends_at_cutoff", max(retrospective$date) == cutoff, max(retrospective$date))
  add_check("ensemble_single_origin", identical(unique(ensemble$origin_date), cutoff), paste(unique(ensemble$origin_date), collapse = ","))
  add_check("ensemble_horizons_1_to_28", identical(sort(unique(ensemble$horizon)), seq_len(28L)), paste(range(ensemble$horizon), collapse = ":"))
  add_check("ensemble_dates_next_28_days", identical(sort(unique(ensemble$target_date)), expected_issued_dates), paste(range(ensemble$target_date), collapse = ":"))
  member_counts <- table(ensemble$horizon)
  add_check("ensemble_51_members_per_horizon", length(member_counts) == 28L && all(member_counts == 51L), paste(range(member_counts), collapse = ":"))
  add_check("covariate_history_ends_at_cutoff", max(covariate_history$date) == cutoff, max(covariate_history$date))
  add_check("covariate_future_is_next_30_days", identical(covariate_future$date, expected_dates), paste(range(covariate_future$date), collapse = ":"))
  add_check("history_has_no_future_reference", !any(reference_history$date > cutoff), sum(reference_history$date > cutoff))
  add_check("history_has_no_future_covariates", !any(covariate_history$date > cutoff), sum(covariate_history$date > cutoff))
  forbidden <- unique(unlist(lapply(
    list(reference_history, reference_scoring, retrospective, ensemble, covariate_history, covariate_future),
    app_glofas_multicutoff_forbidden_columns
  ), use.names = FALSE))
  add_check("no_forbidden_input_columns", !length(forbidden), paste(forbidden, collapse = ","))
  add_check(
    "finite_nonnegative_streamflow",
    all(is.finite(reference_history$streamflow)) && all(reference_history$streamflow >= 0) &&
      all(is.finite(reference_scoring$streamflow)) && all(reference_scoring$streamflow >= 0) &&
      all(is.finite(retrospective$glofas_streamflow)) && all(retrospective$glofas_streamflow >= 0) &&
      all(is.finite(ensemble$glofas_streamflow)) && all(ensemble$glofas_streamflow >= 0),
    "reference, retrospective, and ensemble"
  )
  audit <- do.call(rbind, checks)
  if (any(audit$status != "pass")) {
    stop(
      sprintf("Alternate-cutoff bundle audit failed: %s.", paste(audit$check[audit$status != "pass"], collapse = ", ")),
      call. = FALSE
    )
  }
  list(
    paths = paths,
    contract = contract,
    audit = audit,
    reference_history = reference_history,
    reference_scoring = reference_scoring,
    retrospective = retrospective,
    ensemble = ensemble,
    covariate_history = covariate_history,
    covariate_future = covariate_future
  )
}

app_glofas_multicutoff_manifest_row <- function(
    input_id,
    source_name,
    source_type,
    local_path,
    upstream_reference,
    cutoff_date,
    notes) {
  profile <- app_table_profile(local_path, intersect(c("date", "origin_date", "target_date"), names(app_read_csv(local_path))))
  data.frame(
    input_id = input_id,
    source_name = source_name,
    source_type = source_type,
    local_path = normalizePath(local_path, mustWork = TRUE),
    upstream_reference = upstream_reference,
    date_min = as.character(profile$date_min),
    date_max = as.character(profile$date_max),
    cutoff_date = as.character(as.Date(cutoff_date)),
    row_count = profile$row_count,
    column_count = profile$column_count,
    sha256 = app_sha256_file(local_path),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

app_glofas_multicutoff_materialize_inputs <- function(bundle_root, runtime_root, cutoff_date) {
  validated <- app_glofas_multicutoff_validate_bundle(bundle_root, cutoff_date)
  cutoff <- as.Date(cutoff_date)
  inputs_dir <- file.path(runtime_root, "inputs")
  configs_dir <- file.path(runtime_root, "configs")
  manifests_dir <- file.path(runtime_root, "manifests")
  for (path in c(inputs_dir, configs_dir, manifests_dir)) app_ensure_dir(path)

  reference <- rbind(validated$reference_history, validated$reference_scoring)
  reference <- reference[order(reference$date), c("date", "station_id", "streamflow"), drop = FALSE]
  covariates <- rbind(validated$covariate_history, validated$covariate_future)
  covariates <- covariates[order(covariates$date), c("date", "ppt", "soil"), drop = FALSE]
  retrospective <- validated$retrospective
  ensemble <- validated$ensemble
  reference_path <- file.path(inputs_dir, "reference_gauge_with_scoring_sidecar.csv")
  retrospective_path <- file.path(inputs_dir, "glofas_retrospective.csv")
  ensemble_path <- file.path(inputs_dir, "glofas_ensemble.csv")
  covariate_path <- file.path(inputs_dir, "ppt_soil_history_and_oracle_future.csv")
  app_write_csv(reference, reference_path)
  app_write_csv(retrospective, retrospective_path)
  app_write_csv(ensemble, ensemble_path)
  app_write_csv(covariates, covariate_path)

  manifest <- do.call(rbind, list(
    app_glofas_multicutoff_manifest_row(
      "reference_gauge", "reference gauge streamflow", "observation", reference_path,
      validated$paths[["reference_history"]], cutoff,
      "Historical USGS through cutoff plus the next 30 days retained only for the physically separate post-fit scoring sidecar."
    ),
    app_glofas_multicutoff_manifest_row(
      "glofas_retrospective", "GloFAS retrospective streamflow", "retrospective_forecast", retrospective_path,
      validated$paths[["retrospective"]], cutoff,
      "Cutoff-specific retrospective series ending exactly at the cutoff."
    ),
    app_glofas_multicutoff_manifest_row(
      "glofas_ensemble", "GloFAS issued ensemble", "ensemble_forecast", ensemble_path,
      validated$paths[["ensemble"]], cutoff,
      "Cutoff-specific 51-member issued ensemble for horizons 1 through 28."
    ),
    app_glofas_multicutoff_manifest_row(
      "ppt_soil_covariates", "PRISM precipitation and ERA5 soil moisture", "covariate", covariate_path,
      paste(validated$paths[c("covariate_history", "covariate_future")], collapse = " | "), cutoff,
      "Realized PRISM precipitation and ERA5 soil moisture; future values are oracle covariates and never include future USGS."
    )
  ))
  input_manifest_path <- file.path(manifests_dir, "input_manifest.csv")
  bundle_audit_path <- file.path(manifests_dir, "bundle_contract_audit.csv")
  app_write_csv(manifest, input_manifest_path)
  app_write_csv(validated$audit, bundle_audit_path)

  cutoff_table <- data.frame(
    cutoff_id = paste0("cutoff_", format(cutoff, "%Y%m%d")),
    origin_date = as.character(cutoff),
    train_start = "1979-02-01",
    train_end = as.character(cutoff),
    eval_start = as.character(cutoff + 1L),
    eval_end = as.character(cutoff + 30L),
    horizon_min = 1L,
    horizon_max = 30L,
    split = "transfer_diagnostic",
    enabled = TRUE,
    notes = "Alternate-cutoff transferability experiment; future USGS is scoring-only.",
    stringsAsFactors = FALSE
  )
  cutoff_path <- file.path(configs_dir, "cutoff.csv")
  app_write_csv(cutoff_table, cutoff_path)
  list(
    input_manifest = manifest,
    input_manifest_path = input_manifest_path,
    cutoff = cutoff_table,
    cutoff_path = cutoff_path,
    bundle_audit_path = bundle_audit_path
  )
}

app_glofas_multicutoff_prepare_normal_transfer <- function(
    base_config_path,
    anchor_manifest_path,
    bundle_root,
    runtime_root,
    run_label,
    cutoff_date,
    max_iter = 100L,
    min_iter = 30L,
    tol = 0.01,
    freeze_beta_warmup_iters = 20L,
    min_beta_updates = 10L,
    n_draws = 500L) {
  runtime_root <- app_resolve_path(runtime_root, must_work = FALSE)
  materialized <- app_glofas_multicutoff_materialize_inputs(bundle_root, runtime_root, cutoff_date)
  cfg <- app_read_config(app_resolve_path(base_config_path, must_work = TRUE))
  cfg$application_name <- paste0(run_label, "_base")
  cfg$description <- sprintf(
    "Alternate-cutoff Normal Ridge/RHS transfer experiment at %s using only the frozen Dec-25 winner specification; no Dec-25 fitted state is transferred.",
    as.character(as.Date(cutoff_date))
  )
  cfg$paths$input_manifest <- normalizePath(materialized$input_manifest_path, mustWork = TRUE)
  cfg$paths$cutoffs <- normalizePath(materialized$cutoff_path, mustWork = TRUE)
  cfg$paths$schema <- normalizePath(app_config_path(cfg, "schema"), mustWork = TRUE)
  cfg$forecast_protocol$require_no_target_leakage <- TRUE
  base_runtime_config <- file.path(runtime_root, "configs", "base_config.yaml")
  app_write_yaml(cfg, base_runtime_config)

  bundle <- app_glofas_part4_prepare_bundle(
    base_config_path = base_runtime_config,
    anchor_manifest_path = anchor_manifest_path,
    run_label = run_label,
    runtime_root = runtime_root,
    require_frozen = TRUE,
    allow_forbidden_sources = FALSE,
    dry_run = TRUE,
    write_candidate_configs = TRUE,
    require_input_files = TRUE,
    max_iter = max_iter,
    min_iter = min_iter,
    tol = tol,
    freeze_beta_warmup_iters = freeze_beta_warmup_iters,
    min_beta_updates = min_beta_updates,
    n_draws = n_draws
  )
  keep <- bundle$manifest$part4_family %in% c("normal_ridge_diagnostic", "normal_rhs_vb_diagnostic")
  manifest <- bundle$manifest[keep, , drop = FALSE]
  if (nrow(manifest) != 2L) stop("Expected exactly two Normal transfer jobs.", call. = FALSE)
  manifest$status <- c("ready_after_operator_launch_approval", "blocked_until_dependencies_complete")
  app_write_csv(manifest, bundle$manifest_path)

  unused <- setdiff(bundle$manifest$run_id, manifest$run_id)
  unlink(file.path(runtime_root, "configs", unused), recursive = TRUE, force = TRUE)
  source_anchor <- app_read_csv(app_resolve_path(anchor_manifest_path, must_work = TRUE))
  historical <- source_anchor$role == "historical_joint_anchor"
  if (any(historical)) {
    source_anchor$fit_object_path[historical] <- ""
    source_anchor$fit_object_sha256[historical] <- ""
    source_anchor$design_hash[historical] <- ""
  }
  fitted_paths <- as.character(source_anchor$fit_object_path %||% "")
  if (any(!is.na(fitted_paths) & nzchar(trimws(fitted_paths)))) {
    stop("Transfer anchor manifest unexpectedly contains fitted object paths.", call. = FALSE)
  }
  app_write_csv(source_anchor, file.path(runtime_root, "configs", "selected_anchor_manifest.csv"))

  transfer_contract <- data.frame(
    field = c(
      "cutoff_date", "forecast_start", "forecast_end", "issued_horizon", "requested_horizon",
      "transferred", "not_transferred", "ridge_initializer", "rhs_initializer",
      "response_scale", "future_usgs_policy"
    ),
    value = c(
      as.character(as.Date(cutoff_date)), as.character(as.Date(cutoff_date) + 1L),
      as.character(as.Date(cutoff_date) + 30L), "28", "30",
      "DESN geometry, lag structure, reservoir seeds, and prior hyperparameters only",
      "Dec-25 coefficients, posterior moments, latent paths, fitted scalers, or sufficient statistics",
      "cold within-cutoff Normal Ridge",
      "exact same-cutoff Normal Ridge dependency fit with 20 coefficient-freeze iterations",
      "log1p", "future USGS physically excluded from fit and used only after fitting for scoring"
    ),
    stringsAsFactors = FALSE
  )
  transfer_contract_path <- file.path(runtime_root, "manifests", "transfer_contract.csv")
  app_write_csv(transfer_contract, transfer_contract_path)
  control_paths <- c(
    materialized$input_manifest_path,
    materialized$cutoff_path,
    materialized$bundle_audit_path,
    file.path(runtime_root, "configs", "selected_anchor_manifest.csv"),
    bundle$manifest_path,
    transfer_contract_path
  )
  controls <- data.frame(
    path = vapply(control_paths, normalizePath, character(1L), mustWork = TRUE),
    sha256 = vapply(control_paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_write_csv(controls, file.path(runtime_root, "manifests", "prelaunch_control_hashes.csv"))
  list(
    runtime_root = runtime_root,
    manifest = manifest,
    transfer_contract = transfer_contract,
    controls = controls
  )
}
