# Build the forecast-origin panel for the GloFAS Q-DESN application.

app_manifest_path <- function(manifest, input_id) {
  idx <- match(input_id, manifest$input_id)
  if (is.na(idx)) stop(sprintf("Input manifest does not contain input_id '%s'.", input_id), call. = FALSE)
  path <- manifest$local_path[[idx]]
  if (grepl("^/", path)) path else app_path(path)
}

app_transform_value <- function(x, method) {
  method <- tolower(as.character(method %||% "identity"))
  if (method == "identity") return(as.numeric(x))
  if (method == "log1p") return(log1p(pmax(as.numeric(x), 0)))
  stop(sprintf("Unknown transformation method '%s'.", method), call. = FALSE)
}

app_load_application_inputs <- function(manifest, schema) {
  ref <- app_read_table(app_manifest_path(manifest, "reference_gauge"))
  ret <- app_read_table(app_manifest_path(manifest, "glofas_retrospective"))
  ens <- app_read_table(app_manifest_path(manifest, "glofas_ensemble"))

  app_check_required_columns(ref, schema$inputs$reference_gauge$required_columns, "reference_gauge")
  app_check_required_columns(ret, schema$inputs$glofas_retrospective$required_columns, "glofas_retrospective")
  app_check_required_columns(ens, schema$inputs$glofas_ensemble$required_columns, "glofas_ensemble")

  list(reference_gauge = ref, glofas_retrospective = ret, glofas_ensemble = ens)
}

app_build_application_panel <- function(cfg, manifest, schema) {
  inputs <- app_load_application_inputs(manifest, schema)
  ref <- inputs$reference_gauge
  ret <- inputs$glofas_retrospective
  ens <- inputs$glofas_ensemble

  ref$date <- as.Date(ref$date)
  ret$date <- as.Date(ret$date)
  ens$origin_date <- as.Date(ens$origin_date)
  ens$target_date <- as.Date(ens$target_date)
  ens$horizon <- as.integer(ens$horizon)

  ref_small <- ref[, c("date", "streamflow"), drop = FALSE]
  names(ref_small) <- c("target_date", "y_reference")

  hist <- merge(
    ret,
    ref_small,
    by.x = "date",
    by.y = "target_date",
    all.x = TRUE,
    sort = FALSE
  )
  hist$origin_date <- hist$date
  hist$target_date <- hist$date
  hist$horizon <- 0L
  hist$member <- NA_character_
  hist$is_retrospective <- TRUE
  hist$is_ensemble <- FALSE
  hist$g_glofas <- hist$glofas_streamflow

  ens_panel <- merge(
    ens,
    ref_small,
    by = "target_date",
    all.x = TRUE,
    sort = FALSE
  )
  ens_panel$date <- as.Date(NA)
  ens_panel$is_retrospective <- FALSE
  ens_panel$is_ensemble <- TRUE
  ens_panel$g_glofas <- ens_panel$glofas_streamflow

  keep <- c(
    "origin_date", "target_date", "horizon", "member", "is_retrospective",
    "is_ensemble", "y_reference", "g_glofas"
  )
  panel <- rbind(hist[, keep, drop = FALSE], ens_panel[, keep, drop = FALSE])

  panel$y_transformed <- app_transform_value(panel$y_reference, cfg$data$transform$response)
  panel$g_transformed <- app_transform_value(panel$g_glofas, cfg$data$transform$forecast)
  panel$split <- "unassigned"
  panel$cutoff_id <- NA_character_

  if (app_covariates_enabled(cfg)) {
    cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
    if (!nrow(cutoffs)) stop("Covariates are enabled but no cutoff row is available.", call. = FALSE)
    cutoff_row <- cutoffs[1L, , drop = FALSE]
    for (nm in c("origin_date", "train_start", "train_end", "eval_start", "eval_end")) {
      cutoff_row[[nm]] <- as.Date(cutoff_row[[nm]])
    }
    timeline <- app_build_model_covariate_timeline(
      cfg = cfg,
      manifest = manifest,
      cutoff_row = cutoff_row,
      panel = panel
    )
    panel <- app_attach_model_covariates(panel, timeline)
  }

  if (isTRUE(cfg$data$calendar$require_target_date_equals_origin_plus_horizon)) {
    idx <- which(panel$is_ensemble)
    bad <- idx[!is.na(panel$target_date[idx]) & !is.na(panel$origin_date[idx]) &
                 as.integer(panel$target_date[idx] - panel$origin_date[idx]) != panel$horizon[idx]]
    if (length(bad)) {
      stop(sprintf("Found %d ensemble rows where target_date - origin_date does not equal horizon.", length(bad)), call. = FALSE)
    }
  }

  panel
}

app_panel_summary <- function(panel) {
  data.frame(
    n_rows = nrow(panel),
    n_retrospective = sum(panel$is_retrospective, na.rm = TRUE),
    n_ensemble = sum(panel$is_ensemble, na.rm = TRUE),
    date_min = as.character(min(panel$target_date, na.rm = TRUE)),
    date_max = as.character(max(panel$target_date, na.rm = TRUE)),
    horizon_min = suppressWarnings(min(panel$horizon, na.rm = TRUE)),
    horizon_max = suppressWarnings(max(panel$horizon, na.rm = TRUE)),
    n_members = length(unique(na.omit(panel$member))),
    n_missing_reference = sum(is.na(panel$y_reference)),
    n_missing_glofas = sum(is.na(panel$g_glofas)),
    stringsAsFactors = FALSE
  )
}

app_validate_panel <- function(panel, schema) {
  app_check_required_columns(panel, schema$derived_panel$required_columns, "derived application panel")
  ens <- panel[panel$is_ensemble, , drop = FALSE]
  if (nrow(ens)) {
    key <- paste(ens$origin_date, ens$target_date, ens$horizon, ens$member, sep = "|")
    if (anyDuplicated(key)) stop("Ensemble panel has duplicate origin-target-horizon-member rows.", call. = FALSE)
    bad_h <- as.integer(ens$target_date - ens$origin_date) != ens$horizon
    if (any(bad_h, na.rm = TRUE)) stop("Ensemble panel has inconsistent horizon definitions.", call. = FALSE)
  }
  invisible(TRUE)
}
