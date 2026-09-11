if (!exists("app_set_repo_root", mode = "function")) {
  source("application/R/00_packages.R")
  app_set_repo_root(getwd())
}
for (path in c(
  "input_contract.R", "feature_contract.R", "glofas_part4_latent_family.R",
  "glofas_part4_multicutoff_normal_transfer.R"
)) source(app_path("application/R", path))

cutoff <- as.Date("2021-12-21")
cutoff_row <- data.frame(
  origin_date = cutoff,
  train_end = cutoff,
  eval_start = cutoff + 1L,
  eval_end = cutoff + 30L,
  horizon_max = 30L
)
window <- app_glofas_part4_window_from_cutoff(cutoff_row)
stopifnot(identical(window$cutoff, cutoff))
stopifnot(identical(window$forecast_start, as.Date("2021-12-22")))
stopifnot(identical(window$requested_forecast_end, as.Date("2022-01-20")))
stopifnot(identical(window$issued_forecast_end, as.Date("2022-01-18")))
stopifnot(window$requested_horizon == 30L, window$issued_horizon == 28L)

root <- tempfile("part4_multicutoff_bundle_")
runtime <- tempfile("part4_multicutoff_runtime_")
dirs <- c("reference", "evaluation", "glofas", "covariates", "metadata")
for (directory in dirs) dir.create(file.path(root, directory), recursive = TRUE, showWarnings = FALSE)
history_dates <- cutoff - 1:0
future_dates <- cutoff + seq_len(30L)
app_write_csv(
  data.frame(date = history_dates, station_id = 11160500, streamflow = c(1, 2)),
  file.path(root, "reference/reference_gauge_history.csv")
)
app_write_csv(
  data.frame(date = future_dates, station_id = 11160500, streamflow = seq_len(30L)),
  file.path(root, "evaluation/reference_gauge_scoring_only_30d.csv")
)
app_write_csv(
  data.frame(date = history_dates, location_id = "site_11160500", glofas_streamflow = c(1.5, 2.5)),
  file.path(root, "glofas/glofas_retrospective.csv")
)
ensemble <- expand.grid(horizon = seq_len(28L), member = sprintf("member_%02d", 0:50), KEEP.OUT.ATTRS = FALSE)
ensemble$origin_date <- cutoff
ensemble$target_date <- cutoff + ensemble$horizon
ensemble$glofas_streamflow <- 1 + ensemble$horizon / 100
ensemble <- ensemble[c("origin_date", "target_date", "horizon", "member", "glofas_streamflow")]
app_write_csv(ensemble, file.path(root, "glofas/glofas_ensemble.csv"))
app_write_csv(
  data.frame(date = history_dates, ppt = c(0, 1), soil = c(0.2, 0.3)),
  file.path(root, "covariates/ppt_soil_history.csv")
)
app_write_csv(
  data.frame(date = future_dates, ppt = rep(0, 30L), soil = rep(0.3, 30L)),
  file.path(root, "covariates/ppt_soil_oracle_future_30d.csv")
)
app_write_csv(
  data.frame(
    cutoff_date = cutoff,
    forecast_start = cutoff + 1L,
    forecast_end = cutoff + 30L,
    requested_horizon_days = 30L,
    glofas_ensemble_horizon_days = 28L,
    missing_glofas_ensemble_horizons = "29,30",
    usgs_site = "11160500",
    retrospective_product = "test",
    realized_covariates = "PRISM precipitation; ERA5 soil moisture",
    excluded_inputs = "NWS; GEFS; PCA",
    future_usgs_policy = "scoring_only_never_model_input"
  ),
  file.path(root, "metadata/bundle_contract.csv")
)

validated <- app_glofas_multicutoff_validate_bundle(root, cutoff)
stopifnot(all(validated$audit$status == "pass"))
materialized <- app_glofas_multicutoff_materialize_inputs(root, runtime, cutoff)
stopifnot(nrow(materialized$input_manifest) == 4L)
stopifnot(all(file.exists(materialized$input_manifest$local_path)))
stopifnot(materialized$cutoff$origin_date[[1L]] == "2021-12-21")
stopifnot(materialized$cutoff$eval_end[[1L]] == "2022-01-20")
stopifnot(nrow(app_read_csv(materialized$input_manifest$local_path[materialized$input_manifest$input_id == "reference_gauge"])) == 32L)

unlink(c(root, runtime), recursive = TRUE, force = TRUE)
cat("GloFAS Part 4 multicutoff Normal transfer tests passed.\n")

