# Materialize audited jerez cutoff snapshots into the article input schema.

app_authoritative_find_input <- function(source_root, candidates, label) {
  paths <- file.path(source_root, candidates)
  hit <- paths[file.exists(paths)]
  if (length(hit)) return(hit[[1L]])
  stop(
    sprintf(
      "Missing required authoritative %s input. Tried: %s",
      label,
      paste(paths, collapse = "; ")
    ),
    call. = FALSE
  )
}

app_authoritative_meta_path <- function(source_root) {
  candidates <- file.path(source_root, c("meta.yaml", "forecats_bundle/meta.yaml"))
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[[1L]] else NA_character_
}

app_authoritative_meta_source_id <- function(source_root) {
  meta_path <- app_authoritative_meta_path(source_root)
  if (is.na(meta_path) || !file.exists(meta_path)) return(NA_character_)
  meta <- tryCatch(app_read_yaml(meta_path), error = function(e) list())
  source_id <- meta$histfix$glofas_source_id %||%
    meta$config$inputs$retros$selection_policy$glofas_by_cutoff_windows[[1L]]$source_id %||%
    NA_character_
  as.character(source_id)[[1L]]
}

app_authoritative_retrospective_storage_scale <- function(source_root) {
  meta_path <- app_authoritative_meta_path(source_root)
  if (is.na(meta_path) || !file.exists(meta_path)) return("raw_cms")
  meta <- tryCatch(app_read_yaml(meta_path), error = function(e) list())
  scale <- meta$storage_scales$retros_daily %||%
    meta$storage_scales$retros %||%
    "raw_cms"
  as.character(scale)[[1L]]
}

app_authoritative_to_raw_cms <- function(x, storage_scale, label) {
  x <- as.numeric(x)
  scale <- tolower(as.character(storage_scale %||% "raw_cms")[[1L]])
  if (scale %in% c("raw", "raw_cms", "cms", "cubic_meters_per_second")) return(x)
  if (scale %in% c("log1p", "log1p_cms", "log1p_raw_cms")) return(expm1(x))
  stop(
    sprintf(
      "Unsupported storage scale '%s' for %s. Add an explicit conversion before materializing.",
      storage_scale,
      label
    ),
    call. = FALSE
  )
}

app_authoritative_select_long_retrospective <- function(retros_daily, cutoff_date, requirements) {
  app_check_required_columns(
    retros_daily,
    c("date", "source_id", "source_label", "source_family", "discharge_cms"),
    "authoritative retrospective daily file"
  )
  spec <- app_glofas_version_spec(cutoff_date, requirements)
  candidates <- retros_daily[retros_daily$source_family == "glofas_historical", , drop = FALSE]
  if (!nrow(candidates)) {
    stop("No GloFAS historical rows found in retros_daily.csv.", call. = FALSE)
  }
  keep <- vapply(seq_len(nrow(candidates)), function(i) {
    row_text <- tolower(paste(candidates$source_id[[i]], candidates$source_label[[i]]))
    app_has_any_fixed(row_text, spec$aliases) && !app_has_any_fixed(row_text, spec$disallowed)
  }, logical(1L))
  out <- candidates[keep, , drop = FALSE]
  if (!nrow(out)) {
    stop(
      sprintf(
        "No GloFAS retrospective rows matched expected source '%s'. Available source ids: %s",
        spec$expected,
        paste(unique(candidates$source_id), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  out
}

app_authoritative_retrospective_from_legacy_schema <- function(
    retros_daily,
    source_root,
    cutoff_date,
    requirements,
    storage_scale = "raw_cms") {
  app_check_required_columns(retros_daily, c("Date", "GloFAS"), "authoritative histfix retrospective file")
  spec <- app_glofas_version_spec(cutoff_date, requirements)
  source_id <- app_authoritative_meta_source_id(source_root)
  if (is.na(source_id) || !nzchar(source_id)) source_id <- spec$expected
  source_text <- tolower(source_id)
  if (!app_has_any_fixed(source_text, spec$aliases) || app_has_any_fixed(source_text, spec$disallowed)) {
    stop(
      sprintf(
        "Histfix metadata source id '%s' does not match expected GloFAS source '%s'.",
        source_id,
        spec$expected
      ),
      call. = FALSE
    )
  }
  data.frame(
    date = as.Date(retros_daily$Date),
    source_id = source_id,
    source_label = sprintf("GloFAS historical source %s", source_id),
    source_family = "glofas_historical",
    discharge_cms = app_authoritative_to_raw_cms(
      retros_daily$GloFAS,
      storage_scale,
      "legacy-schema GloFAS retrospective"
    ),
    stringsAsFactors = FALSE
  )
}

app_authoritative_retrospective_rows <- function(source_root, cutoff_date, requirements) {
  path <- app_authoritative_find_input(
    source_root,
    c("inputs/retros_daily.csv", "forecats_bundle/inputs/retros_daily.csv"),
    "GloFAS retrospective"
  )
  retros_daily <- app_read_csv(path)
  storage_scale <- app_authoritative_retrospective_storage_scale(source_root)
  if (all(c("date", "source_id", "source_label", "source_family", "discharge_cms") %in% names(retros_daily))) {
    out <- app_authoritative_select_long_retrospective(retros_daily, cutoff_date, requirements)
  } else if (all(c("Date", "GloFAS") %in% names(retros_daily))) {
    out <- app_authoritative_retrospective_from_legacy_schema(
      retros_daily,
      source_root,
      cutoff_date,
      requirements,
      storage_scale = storage_scale
    )
  } else {
    stop(
      sprintf(
        "Unsupported authoritative retrospective schema in %s. Columns: %s",
        path,
        paste(names(retros_daily), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  out$date <- as.Date(out$date)
  out <- out[out$date <= as.Date(cutoff_date), , drop = FALSE]
  if (!nrow(out)) {
    stop(
      sprintf("No GloFAS retrospective rows remain through cutoff_date %s.", as.Date(cutoff_date)),
      call. = FALSE
    )
  }
  attr(out, "source_path") <- path
  attr(out, "storage_scale") <- storage_scale
  out
}

app_materialize_authoritative_cutoff_bundle <- function(
    source_root,
    cutoff_date,
    bundle_root,
    station_id = "11160500",
    requirements_path = "application/config/authoritative_source_requirements.yaml",
    glofas_source_root = NULL,
    overwrite = TRUE) {
  source_root <- app_resolve_path(source_root, must_work = TRUE)
  glofas_source_root <- app_resolve_path(glofas_source_root %||% source_root, must_work = TRUE)
  bundle_root <- app_resolve_path(bundle_root, must_work = FALSE)
  cutoff_date <- as.Date(cutoff_date)
  if (is.na(cutoff_date)) stop("cutoff_date must be a valid date.", call. = FALSE)
  requirements <- app_read_yaml(app_resolve_path(requirements_path, must_work = TRUE))

  if (dir.exists(bundle_root) && !isTRUE(overwrite)) {
    stop(sprintf("Bundle root already exists: %s", bundle_root), call. = FALSE)
  }

  reference_dir <- file.path(bundle_root, "reference")
  glofas_dir <- file.path(bundle_root, "glofas")
  cov_dir <- file.path(bundle_root, "covariates")
  metadata_dir <- file.path(bundle_root, "metadata")
  for (path in c(reference_dir, glofas_dir, cov_dir, metadata_dir)) app_ensure_dir(path)

  read_required <- function(path) {
    if (!file.exists(path)) stop(sprintf("Missing required authoritative input: %s", path), call. = FALSE)
    app_read_csv(path)
  }

  usgs_path <- file.path(source_root, "inputs", "usgs_daily.csv")
  glofas_members_path <- app_authoritative_find_input(
    glofas_source_root,
    c("inputs/glofas_members.csv", "forecats_bundle/inputs/glofas_members.csv"),
    "GloFAS ensemble members"
  )
  ppt_path <- file.path(source_root, "covariates", "cov_03_PPT.csv")
  soil_path <- file.path(source_root, "covariates", "cov_04_SOIL.csv")
  pca_path <- file.path(source_root, "covariates", "cov_05_PCA.csv")

  usgs <- read_required(usgs_path)
  app_check_required_columns(usgs, c("date", "discharge_cms"), "authoritative USGS daily file")
  reference <- data.frame(
    date = as.Date(usgs$date),
    station_id = as.character(station_id),
    streamflow = as.numeric(usgs$discharge_cms),
    stringsAsFactors = FALSE
  )
  reference <- reference[order(reference$date), , drop = FALSE]
  app_write_csv(reference, file.path(reference_dir, "reference_gauge.csv"))

  glofas_retro <- app_authoritative_retrospective_rows(glofas_source_root, cutoff_date, requirements)
  glofas_retro_source_path <- attr(glofas_retro, "source_path") %||% NA_character_
  glofas_retro_storage_scale <- attr(glofas_retro, "storage_scale") %||% NA_character_
  glofas_retrospective <- data.frame(
    date = as.Date(glofas_retro$date),
    location_id = sprintf("site_%s", station_id),
    glofas_streamflow = as.numeric(glofas_retro$discharge_cms),
    source_id = glofas_retro$source_id,
    source_label = glofas_retro$source_label,
    stringsAsFactors = FALSE
  )
  glofas_retrospective <- glofas_retrospective[order(glofas_retrospective$date), , drop = FALSE]
  app_write_csv(glofas_retrospective, file.path(glofas_dir, "glofas_retrospective.csv"))

  glofas_wide <- read_required(glofas_members_path)
  app_check_required_columns(glofas_wide, "target_date", "authoritative GloFAS member file")
  member_cols <- grep("^member_", names(glofas_wide), value = TRUE)
  if (!length(member_cols)) stop("No member_* columns found in GloFAS member file.", call. = FALSE)
  glofas_wide$target_date <- as.Date(glofas_wide$target_date)
  ensemble_rows <- lapply(member_cols, function(member) {
    data.frame(
      origin_date = cutoff_date,
      target_date = glofas_wide$target_date,
      horizon = as.integer(glofas_wide$target_date - cutoff_date),
      member = member,
      glofas_streamflow = as.numeric(glofas_wide[[member]]),
      stringsAsFactors = FALSE
    )
  })
  glofas_ensemble <- do.call(rbind, ensemble_rows)
  glofas_ensemble <- glofas_ensemble[glofas_ensemble$horizon >= 1L, , drop = FALSE]
  glofas_ensemble <- glofas_ensemble[order(glofas_ensemble$target_date, glofas_ensemble$member), , drop = FALSE]
  app_write_csv(glofas_ensemble, file.path(glofas_dir, "glofas_ensemble.csv"))

  wrote_covariates <- FALSE
  wrote_climate_covariates <- FALSE
  if (all(file.exists(c(ppt_path, soil_path)))) {
    ppt <- app_read_csv(ppt_path)
    soil <- app_read_csv(soil_path)
    app_check_required_columns(ppt, c("Date", "PRCP_mm"), "authoritative precipitation covariate")
    app_check_required_columns(soil, c("Date", "Daily_Avg_Soil_Moisture"), "authoritative soil covariate")
    cov <- merge(
      data.frame(date = as.Date(ppt$Date), precipitation_mm = as.numeric(ppt$PRCP_mm)),
      data.frame(date = as.Date(soil$Date), soil_moisture = as.numeric(soil$Daily_Avg_Soil_Moisture)),
      by = "date",
      all = TRUE
    )
    cov <- cov[order(cov$date), , drop = FALSE]
    ppt_soil <- data.frame(
      date = cov$date,
      ppt = cov$precipitation_mm,
      soil = cov$soil_moisture,
      stringsAsFactors = FALSE
    )
    app_write_csv(ppt_soil, file.path(cov_dir, "ppt_soil_covariates.csv"))
    wrote_covariates <- TRUE

    if (file.exists(pca_path)) {
      pca <- app_read_csv(pca_path)
      app_check_required_columns(pca, c("time", "Static_PCA"), "authoritative PCA covariate")
      climate_cov <- merge(
        cov,
        data.frame(date = as.Date(pca$time), gdpc1 = as.numeric(pca$Static_PCA)),
        by = "date",
        all = TRUE
      )
      climate_cov <- climate_cov[order(climate_cov$date), , drop = FALSE]
      app_write_csv(climate_cov, file.path(cov_dir, "climate_covariates.csv"))
      wrote_climate_covariates <- TRUE
    }
  }

  for (name in c("source_map.txt", "snapshot_source_map.json", "data_start_filter_summary.txt")) {
    src <- file.path(source_root, name)
    if (file.exists(src)) file.copy(src, file.path(metadata_dir, name), overwrite = TRUE)
  }
  extra_metadata <- list(
    glofas_histfix_meta = file.path(glofas_source_root, "meta.yaml"),
    glofas_histfix_bundle_health = file.path(glofas_source_root, "bundle_health.json"),
    glofas_histfix_bundle_manifest = file.path(glofas_source_root, "manifests", "bundle_manifest.csv"),
    glofas_retros_source_lineage = file.path(glofas_source_root, "inputs", "retros_source_lineage.csv")
  )
  for (nm in names(extra_metadata)) {
    src <- extra_metadata[[nm]]
    if (file.exists(src)) {
      file.copy(src, file.path(metadata_dir, paste0(nm, ".", tools::file_ext(src))), overwrite = TRUE)
    }
  }

  source_map <- data.frame(
    input_id = c("reference_gauge", "glofas_retrospective", "glofas_ensemble"),
    source_path = c(usgs_path, glofas_retro_source_path, glofas_members_path),
    local_path = c(
      file.path(reference_dir, "reference_gauge.csv"),
      file.path(glofas_dir, "glofas_retrospective.csv"),
      file.path(glofas_dir, "glofas_ensemble.csv")
    ),
    provenance_status = "authoritative_jerez_audited",
    stringsAsFactors = FALSE
  )
  if (isTRUE(wrote_covariates)) {
    source_map <- rbind(
      source_map,
      data.frame(
        input_id = "ppt_soil_covariates",
        source_path = paste(c(ppt_path, soil_path), collapse = "; "),
        local_path = file.path(cov_dir, "ppt_soil_covariates.csv"),
        provenance_status = "authoritative_jerez_audited",
        stringsAsFactors = FALSE
      )
    )
  }
  if (isTRUE(wrote_climate_covariates)) {
    source_map <- rbind(
      source_map,
      data.frame(
        input_id = "climate_covariates",
        source_path = paste(c(ppt_path, soil_path, pca_path), collapse = "; "),
        local_path = file.path(cov_dir, "climate_covariates.csv"),
        provenance_status = "diagnostic_provenance_only",
        stringsAsFactors = FALSE
      )
    )
  }
  app_write_csv(source_map, file.path(metadata_dir, "source_map.csv"))

  summary <- data.frame(
    cutoff_date = as.character(cutoff_date),
    source_root = source_root,
    glofas_source_root = glofas_source_root,
    bundle_root = bundle_root,
    n_reference_rows = nrow(reference),
    n_glofas_retrospective_rows = nrow(glofas_retrospective),
    n_glofas_ensemble_rows = nrow(glofas_ensemble),
    n_glofas_members = length(unique(glofas_ensemble$member)),
    glofas_source_id = paste(unique(glofas_retrospective$source_id), collapse = ";"),
    glofas_retrospective_source_path = glofas_retro_source_path,
    glofas_retrospective_storage_scale = glofas_retro_storage_scale,
    glofas_members_source_path = glofas_members_path,
    wrote_covariates = wrote_covariates,
    wrote_climate_covariates = wrote_climate_covariates,
    retrospective_date_min = as.character(min(glofas_retrospective$date)),
    retrospective_date_max = as.character(max(glofas_retrospective$date)),
    ensemble_target_min = as.character(min(glofas_ensemble$target_date)),
    ensemble_target_max = as.character(max(glofas_ensemble$target_date)),
    stringsAsFactors = FALSE
  )
  app_write_csv(summary, file.path(metadata_dir, "materialization_summary.csv"))
  writeLines(
    c(
      "Authoritative cutoff bundle materialization",
      sprintf("cutoff_date: %s", cutoff_date),
      sprintf("source_root: %s", source_root),
      sprintf("glofas_source_root: %s", glofas_source_root),
      sprintf("bundle_root: %s", bundle_root),
      sprintf("glofas_source_id: %s", summary$glofas_source_id[[1L]]),
      sprintf("glofas_retrospective_source_path: %s", glofas_retro_source_path),
      sprintf("glofas_retrospective_storage_scale: %s", glofas_retro_storage_scale),
      "provenance_status: authoritative_jerez_audited"
    ),
    file.path(metadata_dir, "MATERIALIZATION_SUMMARY.txt")
  )

  list(
    bundle_root = bundle_root,
    summary = summary,
    source_map = source_map
  )
}
