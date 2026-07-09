tmp_root <- tempfile("qdesn_authoritative_materialize_")
dir.create(tmp_root, recursive = TRUE)

make_common_inputs <- function(source_root, cutoff_date) {
  dir.create(file.path(source_root, "inputs"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(source_root, "forecats_bundle", "inputs"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(source_root, "covariates"), recursive = TRUE, showWarnings = FALSE)
  app_write_csv(data.frame(
    date = as.character(as.Date(cutoff_date) - 3:0),
    discharge_cms = c(1.0, 1.2, 1.4, 1.5),
    stringsAsFactors = FALSE
  ), file.path(source_root, "inputs", "usgs_daily.csv"))
  app_write_csv(data.frame(
    target_date = as.character(as.Date(cutoff_date) + 1:3),
    member_00 = c(1.1, 1.2, 1.3),
    member_01 = c(1.2, 1.3, 1.4),
    stringsAsFactors = FALSE
  ), file.path(source_root, "forecats_bundle", "inputs", "glofas_members.csv"))
  app_write_csv(data.frame(
    Date = as.character(as.Date(cutoff_date) - 3:3),
    PRCP_mm = seq(0, 6),
    stringsAsFactors = FALSE
  ), file.path(source_root, "covariates", "cov_03_PPT.csv"))
  app_write_csv(data.frame(
    Date = as.character(as.Date(cutoff_date) - 3:3),
    Daily_Avg_Soil_Moisture = 0.20 + 0.01 * seq(0, 6),
    stringsAsFactors = FALSE
  ), file.path(source_root, "covariates", "cov_04_SOIL.csv"))
}

long_root <- file.path(tmp_root, "long")
make_common_inputs(long_root, "2022-12-25")
app_write_csv(data.frame(
  date = as.character(as.Date("2022-12-20") + 0:2),
  source_id = "glofas_hist_v31_lisflood_cons",
  source_label = "GloFAS historical v3.1 (LISFLOOD, consolidated)",
  source_family = "glofas_historical",
  discharge_cms = c(0.8, 0.9, 1.0),
  stringsAsFactors = FALSE
), file.path(long_root, "forecats_bundle", "inputs", "retros_daily.csv"))

long_bundle <- file.path(tmp_root, "long_bundle")
long_result <- app_materialize_authoritative_cutoff_bundle(
  source_root = long_root,
  cutoff_date = "2022-12-25",
  bundle_root = long_bundle,
  station_id = "toy"
)
long_retro <- app_read_csv(file.path(long_bundle, "glofas", "glofas_retrospective.csv"))
long_ens <- app_read_csv(file.path(long_bundle, "glofas", "glofas_ensemble.csv"))
stopifnot(nrow(long_retro) == 3L)
stopifnot(unique(long_retro$source_id) == "glofas_hist_v31_lisflood_cons")
stopifnot(nrow(long_ens) == 6L)
stopifnot(sort(unique(long_ens$horizon)) == 1:3)
stopifnot(long_result$summary$glofas_source_id == "glofas_hist_v31_lisflood_cons")
stopifnot(file.exists(file.path(long_bundle, "covariates", "ppt_soil_covariates.csv")))
stopifnot(!file.exists(file.path(long_bundle, "covariates", "climate_covariates.csv")))
long_cov <- app_read_csv(file.path(long_bundle, "covariates", "ppt_soil_covariates.csv"))
stopifnot(identical(names(long_cov), c("date", "ppt", "soil")))
stopifnot(isTRUE(long_result$summary$wrote_covariates))
stopifnot(!isTRUE(long_result$summary$wrote_climate_covariates))

base_root <- file.path(tmp_root, "base")
histfix_root <- file.path(tmp_root, "histfix")
make_common_inputs(base_root, "2022-12-25")
dir.create(file.path(histfix_root, "inputs"), recursive = TRUE, showWarnings = FALSE)
file.copy(
  file.path(base_root, "forecats_bundle", "inputs", "glofas_members.csv"),
  file.path(histfix_root, "inputs", "glofas_members.csv"),
  overwrite = TRUE
)
app_write_csv(data.frame(
  Date = as.character(as.Date("2022-12-22") + 0:4),
  USGS = log1p(c(1.0, 1.1, 1.2, 1.3, 1.4)),
  GloFAS = log1p(c(0.6, 0.7, 0.8, 0.9, 1.0)),
  `NWS3.0` = log1p(c(0.8, 0.9, 1.0, 1.1, 1.2)),
  check.names = FALSE,
  stringsAsFactors = FALSE
), file.path(histfix_root, "inputs", "retros_daily.csv"))
writeLines(
  c(
    "histfix:",
    "  glofas_source_id: glofas_hist_v31_lisflood_cons",
    "storage_scales:",
    "  retros_daily: log1p_cms"
  ),
  file.path(histfix_root, "meta.yaml")
)

histfix_bundle <- file.path(tmp_root, "histfix_bundle")
histfix_result <- app_materialize_authoritative_cutoff_bundle(
  source_root = base_root,
  glofas_source_root = histfix_root,
  cutoff_date = "2022-12-25",
  bundle_root = histfix_bundle,
  station_id = "toy"
)
histfix_retro <- app_read_csv(file.path(histfix_bundle, "glofas", "glofas_retrospective.csv"))
stopifnot(nrow(histfix_retro) == 4L)
stopifnot(max(as.Date(histfix_retro$date)) == as.Date("2022-12-25"))
stopifnot(max(abs(histfix_retro$glofas_streamflow - c(0.6, 0.7, 0.8, 0.9))) < 1.0e-10)
stopifnot(histfix_result$summary$glofas_retrospective_storage_scale == "log1p_cms")

legacy_root <- file.path(tmp_root, "legacy")
make_common_inputs(legacy_root, "2022-05-11")
app_write_csv(data.frame(
  Date = as.character(as.Date("2022-05-08") + 0:2),
  USGS = c(1.0, 1.1, 1.2),
  GloFAS = c(0.7, 0.8, 0.9),
  `NWS3.0` = c(0.9, 1.0, 1.1),
  check.names = FALSE,
  stringsAsFactors = FALSE
), file.path(legacy_root, "forecats_bundle", "inputs", "retros_daily.csv"))
dir.create(file.path(legacy_root, "forecats_bundle"), recursive = TRUE, showWarnings = FALSE)
writeLines(
  c(
    "histfix:",
    "  glofas_source_id: glofas_hist_v31_lisflood_cons"
  ),
  file.path(legacy_root, "forecats_bundle", "meta.yaml")
)

legacy_bundle <- file.path(tmp_root, "legacy_bundle")
legacy_result <- app_materialize_authoritative_cutoff_bundle(
  source_root = legacy_root,
  cutoff_date = "2022-05-11",
  bundle_root = legacy_bundle,
  station_id = "toy"
)
legacy_retro <- app_read_csv(file.path(legacy_bundle, "glofas", "glofas_retrospective.csv"))
stopifnot(nrow(legacy_retro) == 3L)
stopifnot(unique(legacy_retro$source_id) == "glofas_hist_v31_lisflood_cons")
stopifnot(all.equal(legacy_retro$glofas_streamflow, c(0.7, 0.8, 0.9)))
stopifnot(legacy_result$summary$glofas_source_id == "glofas_hist_v31_lisflood_cons")
