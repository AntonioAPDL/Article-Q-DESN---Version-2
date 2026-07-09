registry <- app_read_csv(app_path("application/config/authoritative_cutoff_sources.csv"))
required_registry_cols <- c(
  "cutoff_id", "cutoff_date", "station_id", "source_root",
  "glofas_source_root", "bundle_root", "input_bundle_config",
  "expected_retrospective_start", "expected_retrospective_end",
  "expected_glofas_source_id", "retrospective_storage_scale",
  "overlap_comparison_path", "requirements_path",
  "source_audit_bundle_root", "source_audit_extra_roots",
  "enabled", "notes"
)
app_check_required_columns(registry, required_registry_cols, "authoritative cutoff source registry")
stopifnot(nrow(registry) >= 1L)
enabled <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
stopifnot(!anyDuplicated(enabled$cutoff_id))
stopifnot(all(!is.na(as.Date(enabled$cutoff_date))))
stopifnot(all(!is.na(as.Date(enabled$expected_retrospective_start))))
stopifnot(all(!is.na(as.Date(enabled$expected_retrospective_end))))
stopifnot(all(as.Date(enabled$expected_retrospective_start) <= as.Date(enabled$expected_retrospective_end)))
stopifnot(all(nzchar(enabled$source_root)))
stopifnot(all(nzchar(enabled$glofas_source_root)))
stopifnot(all(nzchar(enabled$bundle_root)))
stopifnot(all(nzchar(enabled$expected_glofas_source_id)))
stopifnot(all(tolower(enabled$retrospective_storage_scale) %in% c("raw_cms", "log1p_cms")))
stopifnot(all(file.exists(app_path(enabled$input_bundle_config))))
stopifnot(all(file.exists(app_path(enabled$requirements_path))))
