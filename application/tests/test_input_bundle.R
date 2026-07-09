tmp_bundle <- tempfile("qdesn_bundle_")
dir.create(tmp_bundle, recursive = TRUE)
dir.create(file.path(tmp_bundle, "reference"), recursive = TRUE)
dir.create(file.path(tmp_bundle, "glofas"), recursive = TRUE)

ref <- data.frame(
  date = as.Date("2021-01-01") + 0:3,
  station_id = "site",
  streamflow = c(10, 11, 12, 13)
)
ret <- data.frame(
  date = as.Date("2021-01-01") + 0:3,
  location_id = "site",
  glofas_streamflow = c(9, 10, 13, 12)
)
ens <- expand.grid(
  origin_date = as.Date("2021-01-03") + 0:1,
  horizon = 1:2,
  member = c("m01", "m02"),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
ens$target_date <- ens$origin_date + ens$horizon
ens$glofas_streamflow <- seq_len(nrow(ens)) + 8

app_write_csv(ref, file.path(tmp_bundle, "reference/reference_gauge.csv"))
app_write_csv(ret, file.path(tmp_bundle, "glofas/glofas_retrospective.csv"))
app_write_csv(ens, file.path(tmp_bundle, "glofas/glofas_ensemble.csv"))

tmp_manifest <- tempfile("qdesn_input_manifest_", fileext = ".csv")
tmp_bundle_manifest <- tempfile("qdesn_bundle_manifest_", fileext = ".csv")
bundle_cfg <- list(
  version = 0.1,
  bundle_id = "toy_bundle",
  bundle_root = tmp_bundle,
  manifest_output = tmp_manifest,
  bundle_manifest_output = tmp_bundle_manifest,
  inputs = list(
    reference_gauge = list(source_name = "reference", source_type = "observation", relative_path = "reference/reference_gauge.csv", upstream_reference = "toy", date_columns = list("date"), required = TRUE),
    glofas_retrospective = list(source_name = "retrospective", source_type = "retrospective_forecast", relative_path = "glofas/glofas_retrospective.csv", upstream_reference = "toy", date_columns = list("date"), required = TRUE),
    glofas_ensemble = list(source_name = "ensemble", source_type = "ensemble_forecast", relative_path = "glofas/glofas_ensemble.csv", upstream_reference = "toy", date_columns = list("origin_date", "target_date"), required = TRUE),
    climate_covariates = list(source_name = "covariates", source_type = "covariate", relative_path = "covariates/climate_covariates.csv", upstream_reference = "toy", date_columns = list("date"), required = FALSE)
  )
)
tmp_cfg_path <- tempfile("qdesn_bundle_cfg_", fileext = ".yaml")
app_write_yaml(bundle_cfg, tmp_cfg_path)

registered <- app_register_input_bundle(
  bundle_config_path = tmp_cfg_path,
  schema_path = app_config_path(cfg, "schema"),
  require_files = TRUE
)
stopifnot(isTRUE(registered$ok))
stopifnot(file.exists(tmp_manifest))
stopifnot(file.exists(tmp_bundle_manifest))
stopifnot(all(c("reference_gauge", "glofas_retrospective", "glofas_ensemble") %in% registered$input_manifest$input_id))
stopifnot(!"climate_covariates" %in% registered$input_manifest$input_id)
ens_row <- registered$input_manifest[registered$input_manifest$input_id == "glofas_ensemble", , drop = FALSE]
stopifnot(identical(ens_row$date_min[[1L]], "2021-01-03"))
stopifnot(identical(ens_row$date_max[[1L]], "2021-01-06"))

validated <- app_validate_input_manifest(tmp_manifest, app_config_path(cfg, "schema"), require_files = TRUE)
stopifnot(isTRUE(validated$ok))

bad_manifest <- registered$input_manifest
bad_manifest$row_count[bad_manifest$input_id == "reference_gauge"] <- 999L
bad_manifest_path <- tempfile("qdesn_bad_input_manifest_", fileext = ".csv")
app_write_csv(bad_manifest, bad_manifest_path)
bad_validated <- app_validate_input_manifest(bad_manifest_path, app_config_path(cfg, "schema"), require_files = TRUE)
stopifnot(!isTRUE(bad_validated$ok))
stopifnot(any(grepl("row_count mismatch", bad_validated$issues)))

tmp_run_root <- tempfile("qdesn_bundle_audit_runs_")
tmp_cfg <- cfg
tmp_cfg$paths$input_manifest <- tmp_manifest
tmp_cfg$paths$runs <- tmp_run_root
run_dirs <- app_create_run_dirs(tmp_cfg, run_id = "test_input_bundle_audit")
audit <- app_audit_input_bundle(tmp_cfg, run_dirs = run_dirs)
stopifnot(isTRUE(audit$ok))
stopifnot(file.exists(file.path(run_dirs$tables, "input_bundle_audit.csv")))
stopifnot(file.exists(file.path(run_dirs$tables, "input_profile.csv")))
