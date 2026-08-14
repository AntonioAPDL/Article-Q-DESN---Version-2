# Register frozen local inputs for the GloFAS Q-DESN application.

app_bundle_root <- function(bundle_cfg) {
  root <- bundle_cfg$bundle_root %||% ""
  if (app_is_placeholder(root)) {
    stop("Input bundle config has no usable bundle_root.", call. = FALSE)
  }
  app_resolve_path(root, must_work = FALSE)
}

app_bundle_input_path <- function(bundle_cfg, input_id) {
  spec <- bundle_cfg$inputs[[input_id]]
  if (is.null(spec)) stop(sprintf("Unknown input_id in bundle config: %s", input_id), call. = FALSE)
  if (!is.null(spec$local_path) && !app_is_placeholder(spec$local_path)) {
    return(app_resolve_path(spec$local_path, must_work = FALSE))
  }
  rel <- spec$relative_path %||% ""
  if (app_is_placeholder(rel)) {
    stop(sprintf("%s: no relative_path or local_path is defined.", input_id), call. = FALSE)
  }
  file.path(app_bundle_root(bundle_cfg), rel)
}

app_bundle_manifest_row <- function(bundle_cfg, input_id, status, message = "") {
  spec <- bundle_cfg$inputs[[input_id]]
  required <- isTRUE(spec$required %||% TRUE)
  path <- app_bundle_input_path(bundle_cfg, input_id)
  exists <- file.exists(path)
  profile <- list(row_count = NA_integer_, column_count = NA_integer_, date_min = NA_character_, date_max = NA_character_)
  file_info <- data.frame(
    local_path = path,
    file_size_bytes = NA_real_,
    modified_time = NA_character_,
    stringsAsFactors = FALSE
  )
  sha <- NA_character_

  if (exists) {
    profile <- app_table_profile(path, spec$date_columns %||% character())
    file_info <- app_file_info_row(path)
    sha <- app_sha256_file(path)
  }

  data.frame(
    bundle_id = bundle_cfg$bundle_id %||% NA_character_,
    input_id = input_id,
    source_name = spec$source_name %||% input_id,
    source_type = spec$source_type %||% NA_character_,
    bundle_root = bundle_cfg$bundle_root %||% NA_character_,
    relative_path = spec$relative_path %||% NA_character_,
    local_path = app_prefer_repo_relative_path(path),
    upstream_reference = spec$upstream_reference %||% NA_character_,
    date_min = profile$date_min,
    date_max = profile$date_max,
    cutoff_date = NA_character_,
    row_count = profile$row_count,
    column_count = profile$column_count,
    sha256 = sha,
    file_size_bytes = file_info$file_size_bytes,
    modified_time = file_info$modified_time,
    registered_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    required = required,
    status = status,
    message = message,
    notes = spec$notes %||% NA_character_,
    stringsAsFactors = FALSE
  )
}

app_input_manifest_from_bundle <- function(bundle_rows) {
  existing <- bundle_rows[bundle_rows$status == "ok", , drop = FALSE]
  out <- data.frame(
    input_id = existing$input_id,
    source_name = existing$source_name,
    source_type = existing$source_type,
    local_path = existing$local_path,
    upstream_reference = existing$upstream_reference,
    date_min = existing$date_min,
    date_max = existing$date_max,
    cutoff_date = existing$cutoff_date,
    row_count = existing$row_count,
    column_count = existing$column_count,
    sha256 = existing$sha256,
    created_at = existing$registered_at,
    notes = existing$notes,
    stringsAsFactors = FALSE
  )
  out[app_required_manifest_columns()]
}

app_register_input_bundle <- function(
  bundle_config_path,
  schema_path,
  manifest_output = NULL,
  bundle_manifest_output = NULL,
  require_files = TRUE
) {
  bundle_cfg <- app_read_yaml(bundle_config_path)
  if (is.null(bundle_cfg$inputs) || !length(bundle_cfg$inputs)) {
    stop("Input bundle config has no inputs.", call. = FALSE)
  }

  rows <- list()
  issues <- character()
  for (input_id in names(bundle_cfg$inputs)) {
    spec <- bundle_cfg$inputs[[input_id]]
    required <- isTRUE(spec$required %||% TRUE)
    path <- app_bundle_input_path(bundle_cfg, input_id)
    if (!file.exists(path)) {
      status <- if (required) "missing_required" else "missing_optional"
      msg <- sprintf("%s: missing file %s", input_id, path)
      rows[[input_id]] <- app_bundle_manifest_row(bundle_cfg, input_id, status = status, message = msg)
      if (required && isTRUE(require_files)) issues <- c(issues, msg)
      next
    }
    rows[[input_id]] <- app_bundle_manifest_row(bundle_cfg, input_id, status = "ok")
  }

  bundle_manifest <- do.call(rbind, rows)
  input_manifest <- app_input_manifest_from_bundle(bundle_manifest)

  manifest_output <- manifest_output %||% bundle_cfg$manifest_output
  bundle_manifest_output <- bundle_manifest_output %||% bundle_cfg$bundle_manifest_output
  if (!is.null(bundle_manifest_output)) {
    app_write_csv(bundle_manifest, app_resolve_path(bundle_manifest_output, must_work = FALSE))
  }
  if (!is.null(manifest_output)) {
    app_write_csv(input_manifest, app_resolve_path(manifest_output, must_work = FALSE))
  }

  validation <- NULL
  if (!length(issues)) {
    validation <- app_validate_input_manifest(
      app_resolve_path(manifest_output, must_work = TRUE),
      schema_path,
      require_files = require_files
    )
    if (!validation$ok) issues <- c(issues, validation$issues)
  }

  list(
    ok = length(issues) == 0L,
    issues = issues,
    bundle_manifest = bundle_manifest,
    input_manifest = input_manifest,
    validation = validation
  )
}
