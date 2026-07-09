tmp_cov_root <- tempfile("qdesn_covariates_")
dir.create(tmp_cov_root, recursive = TRUE)
bundle_root <- file.path(tmp_cov_root, "bundle")
handoff_root <- file.path(tmp_cov_root, "handoff")
dir.create(file.path(bundle_root, "covariates"), recursive = TRUE)

dates <- as.Date("2021-01-01") + 0:20
app_write_csv(
  data.frame(
    date = dates,
    ppt = seq_along(dates) - 1,
    soil = 0.20 + 0.01 * seq_along(dates),
    stringsAsFactors = FALSE
  ),
  file.path(bundle_root, "covariates", "ppt_soil_covariates.csv")
)

make_gefs_file <- function(path, target_dates, value_fun) {
  app_ensure_dir(dirname(path))
  rows <- do.call(rbind, lapply(target_dates, function(d) {
    data.frame(
      init_date = "2021-01-10",
      cycle_hour = 0L,
      lead_hours = c(24L, 30L),
      target_time_utc = paste0(as.character(d), c("T00:00:00Z", "T06:00:00Z")),
      target_date = as.character(d),
      member_00 = value_fun(d, 0L, c(24L, 30L)),
      member_01 = value_fun(d, 1L, c(24L, 30L)),
      stringsAsFactors = FALSE
    )
  }))
  app_write_csv(rows, path)
}

make_gefs_file(
  file.path(handoff_root, "forecast_cache/gefs/issue_date=2021-01-10/variable=APCP_surface/gefs_members.csv"),
  as.Date("2021-01-11") + 0:4,
  function(d, member, lead) rep(as.integer(d - as.Date("2021-01-10")) + member, length(lead))
)
make_gefs_file(
  file.path(handoff_root, "forecast_cache/gefs/issue_date=2021-01-10/variable=SOILW_0_0_1_m_below_ground/gefs_members.csv"),
  as.Date("2021-01-11") + 0:4,
  function(d, member, lead) rep(0.30 + 0.01 * as.integer(d - as.Date("2021-01-10")) + 0.02 * member, length(lead))
)

manifest <- data.frame(
  input_id = "ppt_soil_covariates",
  local_path = file.path(bundle_root, "covariates", "ppt_soil_covariates.csv"),
  stringsAsFactors = FALSE
)
cutoff <- data.frame(
  cutoff_id = "toy",
  origin_date = as.Date("2021-01-10"),
  train_start = as.Date("2021-01-01"),
  train_end = as.Date("2021-01-10"),
  eval_start = as.Date("2021-01-11"),
  eval_end = as.Date("2021-01-15"),
  horizon_min = 1L,
  horizon_max = 5L,
  split = "toy",
  enabled = TRUE,
  notes = "",
  stringsAsFactors = FALSE
)
cov_cfg <- cfg
cov_cfg$covariates <- list(
  enabled = TRUE,
  variables = c("ppt", "soil"),
  forecast = list(handoff_root = handoff_root),
  readout = list(lags = c(0L, 1L, 2L), standardize = TRUE, scale_reference = "retrospective_train"),
  ppt = list(
    reduction = "q50",
    dry_day_threshold_mm = 0,
    noisy_blend = list(enabled = FALSE),
    observed_blend = list(enabled = TRUE, observed_weight = 0.5, observed_zero_stay_prob = 0)
  ),
  soil = list(
    reduction = "q50",
    noisy_blend = list(enabled = FALSE),
    observed_blend = list(enabled = TRUE, observed_weight = 0.5)
  )
)
cov_cfg$forecast_protocol$default_horizon_max <- 5L

panel_stub <- data.frame(
  origin_date = as.Date("2021-01-10"),
  target_date = as.Date("2021-01-01") + 0:14,
  horizon = c(rep(0L, 10L), 1:5),
  stringsAsFactors = FALSE
)
timeline <- app_build_model_covariate_timeline(cov_cfg, manifest, cutoff, panel = panel_stub)
stopifnot(!"gdpc1" %in% names(timeline))
stopifnot(all(c("ppt", "soil", "ppt_scaled", "soil_scaled", "ppt_role", "soil_role") %in% names(timeline)))
stopifnot(sum(timeline$ppt_role == "forecast_blended") == 5L)

future_row <- timeline[timeline$date == as.Date("2021-01-12"), , drop = FALSE]
obs_ppt <- 11
gefs_ppt_daily_member_00 <- 2 * 2
gefs_ppt_daily_member_01 <- 2 * 3
expected_ppt_q50 <- mean(c(gefs_ppt_daily_member_00, gefs_ppt_daily_member_01))
stopifnot(abs(future_row$ppt - (0.5 * obs_ppt + 0.5 * expected_ppt_q50)) < 1.0e-12)

panel_cov <- app_attach_model_covariates(panel_stub, timeline)
stopifnot(all(c("ppt", "soil", "model_covariate_role") %in% names(panel_cov)))
lag_mat <- app_covariate_lag_matrix(timeline, as.Date("2021-01-12"), cov_cfg)
stopifnot(identical(colnames(lag_mat), c("ppt_lag_0", "ppt_lag_1", "ppt_lag_2", "soil_lag_0", "soil_lag_1", "soil_lag_2")))
stopifnot(is.matrix(lag_mat) && nrow(lag_mat) == 1L && ncol(lag_mat) == 6L)

base_panel <- data.frame(
  origin_date = as.Date("2021-01-08") + 0:2,
  target_date = as.Date("2021-01-08") + 0:2,
  horizon = 0L,
  stringsAsFactors = FALSE
)
base_panel <- app_copy_covariate_attrs(base_panel, panel_cov)
X_core <- cbind(bias = 1, h1 = c(0.1, 0.2, 0.3))
feature_rows <- app_make_discrepancy_feature_rows(
  base_panel = base_panel,
  X_core = X_core,
  origin_dates = as.Date("2021-01-10"),
  target_dates = as.Date("2021-01-12"),
  horizons = 2L,
  cfg = cov_cfg,
  feature_strategy = "horizon_indexed_origin_state",
  horizon_scale = 5
)
stopifnot(isTRUE(feature_rows$keep[[1L]]))
stopifnot(ncol(feature_rows$X) == ncol(X_core) + ncol(lag_mat) + 1L)
stopifnot("horizon_scaled" %in% colnames(feature_rows$X))

summary <- app_covariate_timeline_summary(timeline)
stopifnot(nrow(summary) == 2L)
stopifnot(all(summary$n_missing == 0L))
stopifnot(all(summary$n_forecast_blended == 5L))
stopifnot(all(summary$future_policy == "gefs_realized_blend"))
stopifnot(all(c("ppt_source_policy", "ppt_source_sha256", "soil_source_provider") %in% names(timeline)))

source_manifest <- app_covariate_source_manifest(timeline)
stopifnot(nrow(source_manifest) >= 4L)
stopifnot(is.character(app_covariate_source_manifest_hash(timeline)))

truncated_manifest <- manifest
truncated_path <- file.path(bundle_root, "covariates", "ppt_soil_covariates_through_cutoff.csv")
app_write_csv(
  data.frame(
    date = dates[dates <= as.Date("2021-01-10")],
    ppt = seq_along(dates[dates <= as.Date("2021-01-10")]) - 1,
    soil = 0.20 + 0.01 * seq_along(dates[dates <= as.Date("2021-01-10")]),
    stringsAsFactors = FALSE
  ),
  truncated_path
)
truncated_manifest$local_path <- truncated_path

gefs_cfg <- cov_cfg
gefs_cfg$covariates$source_policy <- NULL
gefs_cfg$covariates$future_policy <- "gefs_only"
gefs_cfg$covariates$allow_realized_future <- FALSE
gefs_cfg$covariates$ppt$observed_blend <- list(enabled = FALSE, observed_weight = 0, observed_zero_stay_prob = 0)
gefs_cfg$covariates$soil$observed_blend <- list(enabled = FALSE, observed_weight = 0)
gefs_timeline <- app_build_model_covariate_timeline(gefs_cfg, truncated_manifest, cutoff, panel = panel_stub)
stopifnot(all(gefs_timeline$ppt_role[gefs_timeline$date > as.Date("2021-01-10")] == "forecast_gefs"))
gefs_future_row <- gefs_timeline[gefs_timeline$date == as.Date("2021-01-12"), , drop = FALSE]
stopifnot(abs(gefs_future_row$ppt - expected_ppt_q50) < 1.0e-12)
stopifnot(!any(gefs_timeline$ppt_uses_realized_future, na.rm = TRUE))

bad_gefs_cfg <- gefs_cfg
bad_gefs_cfg$covariates$ppt$observed_blend <- list(enabled = TRUE, observed_weight = 0, observed_zero_stay_prob = 0.9)
bad_ok <- tryCatch({
  app_validate_covariate_source_policy(bad_gefs_cfg, truncated_manifest, cutoff, stop_on_failure = TRUE)
  TRUE
}, error = function(e) FALSE)
stopifnot(!bad_ok)

oracle_cfg <- cov_cfg
oracle_cfg$covariates$source_policy <- NULL
oracle_cfg$covariates$future_policy <- "oracle_realized"
oracle_cfg$covariates$allow_realized_future <- TRUE
oracle_cfg$covariates$forecast$handoff_root <- NULL
oracle_timeline <- app_build_model_covariate_timeline(oracle_cfg, manifest, cutoff, panel = panel_stub)
stopifnot(all(oracle_timeline$ppt_role[oracle_timeline$date > as.Date("2021-01-10")] == "oracle_realized"))
oracle_future_row <- oracle_timeline[oracle_timeline$date == as.Date("2021-01-12"), , drop = FALSE]
stopifnot(abs(oracle_future_row$ppt - obs_ppt) < 1.0e-12)
stopifnot(sum(oracle_timeline$ppt_uses_realized_future, na.rm = TRUE) == 5L)
