# Input, schema, and grid validation for the GloFAS Q-DESN application.

app_required_manifest_columns <- function() {
  c(
    "input_id", "source_name", "source_type", "local_path", "upstream_reference",
    "date_min", "date_max", "cutoff_date", "row_count", "column_count",
    "sha256", "created_at", "notes"
  )
}

app_load_input_manifest <- function(path, required = TRUE) {
  if (!file.exists(path)) {
    if (!isTRUE(required)) return(data.frame())
    stop(
      paste(
        "Missing application input manifest.",
        sprintf("Expected: %s", path),
        "Create it from application/manifests/input_manifest_TEMPLATE.csv after placing frozen local inputs.",
        sep = "\n"
      ),
      call. = FALSE
    )
  }
  app_read_csv(path)
}

app_validate_manifest_columns <- function(manifest) {
  missing <- setdiff(app_required_manifest_columns(), names(manifest))
  if (length(missing)) {
    stop(sprintf("Input manifest is missing required columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_is_placeholder <- function(x) {
  z <- trimws(as.character(x))
  is.na(z) | !nzchar(z) | z %in% c("TO_BE_FILLED", "NA", "TBD")
}

app_manifest_date_columns <- function(input_id, schema) {
  spec <- schema$inputs[[input_id]]
  if (is.null(spec)) return(character())
  intersect(c("date", "origin_date", "target_date"), spec$required_columns %||% character())
}

app_compare_manifest_number <- function(row, name, actual, input_id) {
  declared <- row[[name]][[1L]]
  if (app_is_placeholder(declared)) {
    return(sprintf("%s: %s is not filled.", input_id, name))
  }
  value <- suppressWarnings(as.numeric(declared))
  if (!is.finite(value)) {
    return(sprintf("%s: %s is not numeric.", input_id, name))
  }
  if (!identical(as.integer(value), as.integer(actual))) {
    return(sprintf("%s: %s mismatch; manifest has %s but file has %s.", input_id, name, declared, actual))
  }
  character(0)
}

app_compare_manifest_date <- function(row, name, actual, input_id) {
  declared <- row[[name]][[1L]]
  if (app_is_placeholder(declared)) {
    return(sprintf("%s: %s is not filled.", input_id, name))
  }
  value <- suppressWarnings(as.Date(declared))
  if (is.na(value)) {
    return(sprintf("%s: %s is not a valid date.", input_id, name))
  }
  if (!identical(as.character(value), as.character(actual))) {
    return(sprintf("%s: %s mismatch; manifest has %s but file has %s.", input_id, name, declared, actual))
  }
  character(0)
}

app_validate_input_manifest <- function(manifest_path, schema_path, require_files = TRUE) {
  manifest <- app_load_input_manifest(manifest_path, required = TRUE)
  app_validate_manifest_columns(manifest)
  schema <- app_read_yaml(schema_path)

  issues <- character(0)
  if (!nrow(manifest)) issues <- c(issues, "Input manifest has no rows.")

  input_specs <- schema$inputs %||% list()
  required_ids <- names(Filter(function(x) isTRUE(x$required %||% TRUE), input_specs))
  missing_ids <- setdiff(required_ids, manifest$input_id)
  if (length(missing_ids)) {
    issues <- c(issues, sprintf("Manifest is missing required input_id values: %s", paste(missing_ids, collapse = ", ")))
  }

  for (i in seq_len(nrow(manifest))) {
    row <- manifest[i, , drop = FALSE]
    id <- row$input_id[[1L]]
    path <- row$local_path[[1L]]
    if (app_is_placeholder(path)) {
      issues <- c(issues, sprintf("%s: local_path is not filled.", id))
      next
    }
    abs_path <- if (grepl("^/", path)) path else app_path(path)
    if (!file.exists(abs_path)) {
      msg <- sprintf("%s: local file does not exist: %s", id, abs_path)
      if (isTRUE(require_files)) issues <- c(issues, msg)
      next
    }
    declared_hash <- row$sha256[[1L]]
    if (app_is_placeholder(declared_hash)) {
      issues <- c(issues, sprintf("%s: sha256 is not filled.", id))
    } else {
      actual_hash <- app_sha256_file(abs_path)
      if (!identical(tolower(declared_hash), tolower(actual_hash))) {
        issues <- c(issues, sprintf("%s: sha256 mismatch.", id))
      }
    }
    input_spec <- schema$inputs[[id]]
    if (is.null(input_spec)) {
      issues <- c(issues, sprintf("%s: input_id is not defined in expected_schema.yaml.", id))
      next
    }
    profile <- tryCatch(
      app_table_profile(abs_path, app_manifest_date_columns(id, schema)),
      error = function(e) {
        issues <<- c(issues, sprintf("%s: could not read file for profile checks: %s", id, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(profile)) {
      missing_cols <- setdiff(input_spec$required_columns %||% character(), profile$column_names)
      if (length(missing_cols)) {
        issues <- c(issues, sprintf("%s: missing required columns: %s", id, paste(missing_cols, collapse = ", ")))
      }
      issues <- c(issues, app_compare_manifest_number(row, "row_count", profile$row_count, id))
      issues <- c(issues, app_compare_manifest_number(row, "column_count", profile$column_count, id))
      if (!is.na(profile$date_min)) {
        issues <- c(issues, app_compare_manifest_date(row, "date_min", profile$date_min, id))
      }
      if (!is.na(profile$date_max)) {
        issues <- c(issues, app_compare_manifest_date(row, "date_max", profile$date_max, id))
      }
    }
  }

  list(
    ok = length(issues) == 0L,
    issues = issues,
    manifest = manifest,
    schema = schema
  )
}

app_validate_quantile_grid <- function(path) {
  qg <- app_read_csv(path)
  required <- c("quantile_id", "quantile_level", "role", "enabled")
  missing <- setdiff(required, names(qg))
  if (length(missing)) stop(sprintf("Quantile grid missing columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  qg <- app_enabled_rows(qg)
  p <- as.numeric(qg$quantile_level)
  if (any(!is.finite(p)) || any(p <= 0 | p >= 1)) {
    stop("Enabled quantile levels must be finite values in (0, 1).", call. = FALSE)
  }
  if (is.unsorted(p, strictly = TRUE)) {
    stop("Enabled quantile levels must be strictly increasing.", call. = FALSE)
  }
  qg$quantile_level <- p
  qg
}

app_validate_cutoffs <- function(path) {
  cutoffs <- app_read_csv(path)
  required <- c(
    "cutoff_id", "origin_date", "train_start", "train_end", "eval_start",
    "eval_end", "horizon_min", "horizon_max", "split", "enabled", "notes"
  )
  missing <- setdiff(required, names(cutoffs))
  if (length(missing)) stop(sprintf("Cutoff file missing columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  if (!nrow(cutoffs)) return(cutoffs)
  cutoffs <- app_enabled_rows(cutoffs)
  date_cols <- c("origin_date", "train_start", "train_end", "eval_start", "eval_end")
  for (nm in date_cols) {
    if (any(is.na(as.Date(cutoffs[[nm]])))) {
      stop(sprintf("Cutoff column '%s' contains non-date values.", nm), call. = FALSE)
    }
  }
  cutoffs
}

app_validate_model_grid <- function(path, schema_path) {
  mg <- app_read_csv(path)
  schema <- app_read_yaml(schema_path)
  required <- schema$model_grid$required_columns
  extra_required <- c("required", "enabled", "notes")
  missing <- setdiff(c(required, extra_required), names(mg))
  if (length(missing)) stop(sprintf("Model grid missing columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  if (anyDuplicated(mg$fit_id)) stop("fit_id values must be unique.", call. = FALSE)
  mg <- app_enabled_rows(mg)
  unknown <- setdiff(unique(mg$model_family), schema$model_grid$allowed_model_families)
  if (length(unknown)) stop(sprintf("Unknown model families: %s", paste(unknown, collapse = ", ")), call. = FALSE)
  p <- as.numeric(mg$quantile_level)
  if (any(!is.finite(p)) || any(p <= 0 | p >= 1)) {
    stop("Enabled model-grid quantile levels must be finite values in (0, 1).", call. = FALSE)
  }
  mg$quantile_level <- p
  mg
}

app_check_required_columns <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}
