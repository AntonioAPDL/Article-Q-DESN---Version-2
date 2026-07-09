tmp_root <- tempfile("qdesn_legacy_prep_")
tmp_legacy <- file.path(tmp_root, "legacy")
tmp_bundle <- file.path(tmp_root, "bundle")
dir.create(tmp_legacy, recursive = TRUE)

app_write_csv(data.frame(
  Date = as.character(as.Date("2022-12-22") + 0:3),
  USGS = c(1.1, 1.2, 1.3, 1.4),
  NWS3.0 = c(1.0, 1.1, 1.2, 1.3),
  GloFAS = c(0.9, 1.0, 1.1, 1.2),
  stringsAsFactors = FALSE
), file.path(tmp_legacy, "retros_2022-12-25.csv"))

app_write_csv(data.frame(
  Date = as.character(as.Date("2022-12-26") + 0:2),
  Ensemble_Member_1 = c(1.3, 1.4, 1.5),
  Ensemble_Member_2 = c(1.2, 1.5, 1.6),
  stringsAsFactors = FALSE
), file.path(tmp_legacy, "glofas_ens_2022-12-25.csv"))

app_write_csv(data.frame(
  Date = as.character(as.Date("2022-12-20") + 0:10),
  Daily_Avg_Log_Streamflow = seq(1, 2, length.out = 11),
  stringsAsFactors = FALSE
), file.path(tmp_legacy, "usgs_daily_avg.csv"))

status <- system2(
  "Rscript",
  c(
    app_path("application/scripts/local_prepare_legacy_cutoff_bundle.R"),
    "--legacy_root", tmp_legacy,
    "--cutoff_date", "2022-12-25",
    "--bundle_root", tmp_bundle,
    "--station_id", "toy_station",
    "--location_id", "toy_glofas",
    "--allow_unverified_legacy", "true"
  ),
  stdout = TRUE,
  stderr = TRUE
)
exit_status <- attr(status, "status") %||% 0L
stopifnot(identical(as.integer(exit_status), 0L))

ref <- app_read_csv(file.path(tmp_bundle, "reference", "reference_gauge.csv"))
ret <- app_read_csv(file.path(tmp_bundle, "glofas", "glofas_retrospective.csv"))
ens <- app_read_csv(file.path(tmp_bundle, "glofas", "glofas_ensemble.csv"))
source_map <- app_read_csv(file.path(tmp_bundle, "metadata", "source_map.csv"))

stopifnot(identical(names(ref), c("date", "station_id", "streamflow")))
stopifnot(identical(names(ret), c("date", "location_id", "glofas_streamflow")))
stopifnot(identical(names(ens), c("origin_date", "target_date", "horizon", "member", "glofas_streamflow")))
stopifnot(nrow(ref) == 7L)
stopifnot(nrow(ret) == 4L)
stopifnot(nrow(ens) == 6L)
stopifnot(sort(unique(ens$horizon)) == 1:3)
stopifnot(length(unique(ens$member)) == 2L)
stopifnot(nrow(source_map) == 3L)
