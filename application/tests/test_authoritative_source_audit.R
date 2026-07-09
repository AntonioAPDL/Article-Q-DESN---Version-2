tmp_root <- tempfile("qdesn_authoritative_audit_")
cutoff_dir <- file.path(tmp_root, "cutoff_date=2022-12-25")
dir.create(cutoff_dir, recursive = TRUE)

writeLines(
  c(
    "{",
    '  "reference": "USGS reference gauge streamflow",',
    '  "glofas_retrospective": "GloFAS LISFLOOD retrospective path",',
    '  "glofas_ensemble": "GloFAS ensemble forecast members",',
    '  "gefs_precipitation": "GEFS precipitation forcing",',
    '  "gefs_soil_moisture": "GEFS SOILW soil moisture forecast input",',
    '  "soil_moisture": "soil moisture forecast input",',
    '  "blend": "weighted custom filled blended forecast input",',
    '  "retro_family": "retrospective source family"',
    "}"
  ),
  file.path(cutoff_dir, "snapshot_source_map.json")
)
writeLines(
  c(
    "data_start_filter_summary",
    "GloFAS hydrological model: glofas_hist_v31_lisflood_cons",
    "GEFS precipitation, GEFS SOILW soil moisture, blended and retrospective inputs present"
  ),
  file.path(cutoff_dir, "data_start_filter_summary.txt")
)
app_write_csv(data.frame(date = "2022-12-25", value = 1), file.path(cutoff_dir, "glofas_lisflood_retrospective.csv"))

ok_result <- app_audit_authoritative_source_bundle(
  bundle_root = tmp_root,
  cutoff_date = "2022-12-25",
  requirements_path = app_path("application/config/authoritative_source_requirements.yaml")
)
stopifnot(isTRUE(ok_result$ok))
stopifnot(all(ok_result$audit$status[ok_result$audit$required] == "ok"))

bad_root <- tempfile("qdesn_authoritative_bad_")
bad_dir <- file.path(bad_root, "cutoff_date=2022-12-25")
dir.create(bad_dir, recursive = TRUE)
writeLines('{"glofas_retrospective":"GloFAS htessel_lisflood retrospective"}', file.path(bad_dir, "snapshot_source_map.json"))
writeLines("missing most required source families", file.path(bad_dir, "data_start_filter_summary.txt"))
bad_result <- app_audit_authoritative_source_bundle(
  bundle_root = bad_root,
  cutoff_date = "2022-12-25",
  requirements_path = app_path("application/config/authoritative_source_requirements.yaml")
)
stopifnot(!isTRUE(bad_result$ok))
stopifnot(any(bad_result$audit$component == "glofas_hydrological_model" & bad_result$audit$status == "failed"))
