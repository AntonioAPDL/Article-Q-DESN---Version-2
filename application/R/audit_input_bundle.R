# Audits for registered GloFAS application inputs.

app_audit_row <- function(check, status, detail, n = NA_integer_) {
  data.frame(
    check = check,
    status = status,
    detail = detail,
    n = n,
    stringsAsFactors = FALSE
  )
}

app_duplicate_count <- function(x, cols) {
  if (!length(cols) || !all(cols %in% names(x))) return(NA_integer_)
  key <- do.call(paste, c(x[cols], sep = "\r"))
  sum(duplicated(key))
}

app_input_profile_rows <- function(manifest, schema) {
  out <- list()
  for (i in seq_len(nrow(manifest))) {
    input_id <- manifest$input_id[[i]]
    path <- app_manifest_path(manifest, input_id)
    x <- app_read_table(path)
    required <- schema$inputs[[input_id]]$required_columns %||% character()
    missing <- setdiff(required, names(x))
    out[[input_id]] <- data.frame(
      input_id = input_id,
      local_path = manifest$local_path[[i]],
      row_count = nrow(x),
      column_count = ncol(x),
      missing_required_columns = paste(missing, collapse = "; "),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out)
}

app_audit_input_bundle <- function(cfg, run_dirs = NULL) {
  manifest_path <- app_config_path(cfg, "input_manifest")
  schema_path <- app_config_path(cfg, "schema")
  validated <- app_validate_input_manifest(manifest_path, schema_path, require_files = TRUE)
  manifest <- validated$manifest
  schema <- validated$schema

  rows <- list(
    manifest = app_audit_row(
      "input manifest validation",
      if (validated$ok) "ok" else "failed",
      if (validated$ok) "Input manifest columns, required IDs, files, and hashes passed." else paste(validated$issues, collapse = "; "),
      nrow(manifest)
    )
  )

  inputs <- list()
  for (id in manifest$input_id) {
    inputs[[id]] <- app_read_table(app_manifest_path(manifest, id))
  }

  if ("reference_gauge" %in% names(inputs)) {
    x <- inputs$reference_gauge
    dups <- app_duplicate_count(x, c("station_id", "date"))
    rows$reference_duplicates <- app_audit_row(
      "reference gauge unique station-date rows",
      if (identical(dups, 0L)) "ok" else "failed",
      sprintf("%s duplicate station-date rows.", dups),
      dups
    )
  }

  if ("glofas_retrospective" %in% names(inputs)) {
    x <- inputs$glofas_retrospective
    dups <- app_duplicate_count(x, c("location_id", "date"))
    rows$retrospective_duplicates <- app_audit_row(
      "GloFAS retrospective unique location-date rows",
      if (identical(dups, 0L)) "ok" else "failed",
      sprintf("%s duplicate location-date rows.", dups),
      dups
    )
  }

  if ("glofas_ensemble" %in% names(inputs)) {
    x <- inputs$glofas_ensemble
    x$origin_date <- as.Date(x$origin_date)
    x$target_date <- as.Date(x$target_date)
    x$horizon <- as.integer(x$horizon)
    dups <- app_duplicate_count(x, c("origin_date", "target_date", "horizon", "member"))
    horizon_bad <- sum(as.integer(x$target_date - x$origin_date) != x$horizon, na.rm = TRUE)
    rows$ensemble_duplicates <- app_audit_row(
      "GloFAS ensemble unique origin-target-horizon-member rows",
      if (identical(dups, 0L)) "ok" else "failed",
      sprintf("%s duplicate ensemble rows.", dups),
      dups
    )
    rows$ensemble_horizon <- app_audit_row(
      "GloFAS ensemble horizon calendar consistency",
      if (identical(horizon_bad, 0L)) "ok" else "failed",
      sprintf("%s rows violate target_date minus origin_date equals horizon.", horizon_bad),
      horizon_bad
    )
  }

  profiles <- app_input_profile_rows(manifest, schema)
  missing_cols <- profiles[nzchar(profiles$missing_required_columns), , drop = FALSE]
  rows$schema_columns <- app_audit_row(
    "required semantic columns",
    if (nrow(missing_cols) == 0L) "ok" else "failed",
    if (nrow(missing_cols) == 0L) "All registered inputs contain required semantic columns." else paste(missing_cols$input_id, collapse = "; "),
    nrow(missing_cols)
  )

  audit <- do.call(rbind, rows)
  if (!is.null(run_dirs)) {
    app_write_csv(audit, file.path(run_dirs$tables, "input_bundle_audit.csv"))
    app_write_csv(profiles, file.path(run_dirs$tables, "input_profile.csv"))
  }
  list(ok = all(audit$status == "ok"), audit = audit, profiles = profiles)
}
