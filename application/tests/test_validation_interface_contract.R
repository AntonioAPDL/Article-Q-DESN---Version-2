iface <- data.frame(
  validation_contract_id = "shared_fitforecast_v2_1p0p0",
  study_id = "shared_fitforecast_v2",
  run_tag = "run",
  model_family = "exdqlm_dqlm",
  model_variant = "dqlm",
  inference = "vb",
  phase = "complete",
  status = "done",
  failure_reason = NA_character_,
  health_gate = "PASS",
  source_registry_root = "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast",
  source_registry_hash_name = "bundle_manifest_sha256",
  source_registry_hash_value = "edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275",
  source_cell_id = "normal_tau0p50",
  scenario_id = "dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast",
  family = "normal",
  tau = 0.5,
  tau_label = "0p50",
  fit_size = 500L,
  effective_fit_size = 500L,
  TT_warmup = 2000L,
  TT_main = 10000L,
  TT_total = 12000L,
  train_start_source_index = 8501L,
  train_end_source_index = 9000L,
  forecast_origin_source_index = 9000L,
  forecast_start_source_index = 9001L,
  forecast_end_source_index = 10000L,
  forecast_h100_start_source_index = 9001L,
  forecast_h100_end_source_index = 9100L,
  forecast_h100_n = 100L,
  forecast_h100_q_mae = 0.4,
  forecast_h100_q_rmse = 0.5,
  forecast_h100_pinball_mean = 0.6,
  forecast_h1000_start_source_index = 9001L,
  forecast_h1000_end_source_index = 10000L,
  forecast_h1000_n = 1000L,
  forecast_h1000_q_mae = 0.7,
  forecast_h1000_q_rmse = 0.8,
  forecast_h1000_pinball_mean = 0.9,
  fit_n = 500L,
  fit_q_mae = 0.1,
  fit_q_rmse = 0.2,
  fit_pinball_mean = 0.3,
  runtime_sec_total = 1,
  row_config_path = "/tmp/row_config.yaml",
  row_status_path = "/tmp/row_status.txt",
  row_health_path = "/tmp/row_health.json",
  row_metrics_path = "/tmp/row_metrics.csv",
  fit_path_summary_path = "/tmp/fit_summary.csv",
  forecast_path_summary_path = "/tmp/forecast_summary.csv",
  log_path = "/tmp/row.log",
  package_version = "1.0.0",
  branch = "validation/shared-fitforecast-v2-1.0.0",
  commit = "e4e6dc0f7976c1464e91231557f9212914e7438a",
  stringsAsFactors = FALSE
)

manifest <- data.frame(
  row_id = 1L,
  row_key = "normal_tau0p50_TT500_dqlm_vb",
  study_id = "shared_fitforecast_v2",
  run_tag = "run",
  scenario_id = "dlm_constV_p90_m0amp_highnoise_steepertrend_v2_TTmain10000_fitforecast",
  source_cell_id = "normal_tau0p50",
  family = "normal",
  tau = 0.5,
  fit_size = 500L,
  model_variant = "dqlm",
  inference = "vb",
  train_start_source_index = 8501L,
  train_end_source_index = 9000L,
  forecast_origin_source_index = 9000L,
  forecast_start_source_index = 9001L,
  forecast_end_source_index = 10000L,
  series_wide_path = "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/example.csv",
  series_wide_sha256 = "edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275",
  stringsAsFactors = FALSE
)

app_validate_shared_fitforecast_interface(iface, manifest)

missing_h1000 <- iface
missing_h1000$forecast_h1000_n <- NA_integer_
h1000_msg <- tryCatch({
  app_validate_shared_fitforecast_interface(missing_h1000, manifest)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("H=1000", h1000_msg, fixed = TRUE))
app_validate_shared_fitforecast_interface(
  missing_h1000,
  manifest,
  require_forecast_metric_counts = FALSE
)

stale <- iface
stale$run_tag <- "feature/qdesn-fitforecast-validation-0p5p0"
stale_msg <- tryCatch({
  app_validate_shared_fitforecast_interface(stale, manifest)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("stale validation source", stale_msg, fixed = TRUE))

missing_hash <- iface
missing_hash$source_registry_hash_value <- ""
hash_msg <- tryCatch({
  app_validate_shared_fitforecast_interface(missing_hash, manifest)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("source registry hash", hash_msg, fixed = TRUE))

missing_origin <- iface
missing_origin$forecast_origin_source_index <- NA_integer_
origin_msg <- tryCatch({
  app_validate_shared_fitforecast_interface(missing_origin, manifest)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("forecast-origin/window metadata", origin_msg, fixed = TRUE))

bad_manifest <- manifest
bad_manifest$forecast_start_source_index <- NA_integer_
window_msg <- tryCatch({
  app_validate_shared_fitforecast_interface(iface, bad_manifest)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("forecast-origin/window metadata", window_msg, fixed = TRUE))

make_required_frame <- function(cols, n) {
  out <- as.data.frame(
    stats::setNames(replicate(length(cols), rep("", n), simplify = FALSE), cols),
    stringsAsFactors = FALSE
  )
  out
}

final_dir <- tempfile("tt500_final_guard_")
dir.create(final_dir, recursive = TRUE, showWarnings = FALSE)
final_interface_path <- file.path(final_dir, "final_interface.csv")
final_config_path <- file.path(final_dir, "final_config.yaml")

final_interface <- make_required_frame(app_required_tt500_final_interface_columns(), 30L)
final_interface$validation_contract_id <- "rolling_origin_v3_lead_interface_v1"
final_interface$interface_schema_version <- "rolling_origin_v3_lead_interface_v1"
final_interface$study_id <- "toy_final_tt500"
final_interface$run_tag <- "toy-final"
final_interface$spec_id <- "qdesn__normal__0p50__tt500__rhs_ns__mcmc__exal__abc123"
final_interface$model_family <- "qdesn"
final_interface$model_variant <- "rhs_ns"
final_interface$inference <- "mcmc"
final_interface$inference_method <- "mcmc"
final_interface$status <- "SUCCESS"
final_interface$health_gate <- "PASS"
final_interface$signoff_grade <- "A"
final_interface$source_registry_root <- "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/toy"
final_interface$source_registry_path <- "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/toy/registry.csv"
final_interface$source_registry_hash_name <- "toy.sha256"
final_interface$source_registry_hash_value <- "toy_registry_hash"
final_interface$source_registry_hash <- "toy_registry_hash"
final_interface$source_cell_id <- "normal_tau0p50"
final_interface$scenario_id <- "toy_dynamic_source"
final_interface$source_path <- "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/toy/source.csv"
final_interface$source_hash <- "toy_source_hash"
final_interface$true_quantile_path <- "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/toy/qtrue.csv"
final_interface$true_quantile_hash <- "toy_qtrue_hash"
final_interface$family <- "normal"
final_interface$tau <- 0.5
final_interface$fit_size <- 500L
final_interface$effective_fit_size <- 500L
final_interface$TT_warmup <- 2000L
final_interface$TT_main <- 10000L
final_interface$TT_total <- 12000L
final_interface$train_start_source_index <- 8501L
final_interface$train_end_source_index <- 9000L
final_interface$forecast_protocol <- "rolling_origin_no_refit_state_update"
final_interface$state_update_method <- "forecast_lattice_observed_lag_state_update_no_refit"
final_interface$refit_per_origin <- FALSE
final_interface$max_lead_configured <- 30L
final_interface$origin_stride <- 30L
final_interface$forecast_origin_source_index <- 9000L
final_interface$forecast_block_start_source_index <- 9001L
final_interface$forecast_block_end_source_index <- 10000L
final_interface$rolling_origin_start_source_index <- 9000L
final_interface$rolling_origin_end_source_index <- 9990L
final_interface$forecast_lead <- seq_len(30L)
final_interface$target_start_source_index <- 9000L + final_interface$forecast_lead
final_interface$target_end_source_index <- 9000L + final_interface$forecast_lead
final_interface$n_origins_scored <- 33L
final_interface$fit_qtrue_mae <- 0.1
final_interface$fit_qtrue_rmse <- 0.2
final_interface$fit_pinball_mean <- 0.3
final_interface$forecast_qtrue_mae <- 0.4
final_interface$forecast_qtrue_rmse <- 0.5
final_interface$forecast_pinball_mean <- 0.6
final_interface$runtime_sec_fit <- 10
final_interface$runtime_sec_forecast <- 2
final_interface$runtime_sec_total <- 12
final_interface$forecast_lead_metrics_path <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/toy/forecast_lead_metrics_scale_repaired.csv"
final_interface$storage_policy <- "storage_light"
final_interface$artifact_manifest_path <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/toy/artifact_manifest.csv"
final_interface$artifact_manifest_hash <- "toy_artifact_hash"
final_interface$compact_path_summary_path <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/toy/path_summary.csv"
final_interface$compact_path_summary_hash <- "toy_path_hash"
final_interface$log_path <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/toy/run.log"
final_interface$config_path <- "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0/toy/config.yaml"
final_interface$config_hash <- "toy_config_hash"
final_interface$package_version <- "1.0.0"
final_interface$validation_branch <- "validation/shared-fitforecast-v2-1.0.0"
final_interface$validation_commit <- "abcdef123456"
app_write_csv(final_interface, final_interface_path)

final_config <- list(
  artifact_id = "toy_tt500_final",
  artifact_status = "final_article_facing_tt500",
  article_consumable = TRUE,
  is_final = TRUE,
  validation_worktree = "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0",
  validation_branch = "validation/shared-fitforecast-v2-1.0.0",
  validation_head_commit_at_article_sync = "abcdef123456",
  package_version = "1.0.0",
  source_registry_root = "/data/jaguir26/local/src/shared_dynamic_fit_forecast_validation/sources/toy",
  source_registry_hash_name = "toy.sha256",
  source_registry_hash_value = "toy_registry_hash",
  fit_size = 500L,
  train_start_source_index = 8501L,
  train_end_source_index = 9000L,
  forecast_origin_source_index = 9000L,
  forecast_block_start_source_index = 9001L,
  forecast_block_end_source_index = 10000L,
  max_lead_configured = 30L,
  origin_stride = 30L,
  forecast_protocol = "rolling_origin_no_refit_state_update",
  interfaces = list(
    toy_qdesn = list(
      model_family = "qdesn",
      interface_role = "toy_qdesn_tt500",
      path = final_interface_path,
      sha256 = app_sha256_file(final_interface_path),
      validation_commit_at_export = "abcdef123456",
      expected_rows_total = 30L,
      expected_rows_tt500 = 30L,
      expected_fit_size_values = list(500L),
      expected_inference_values = list("mcmc"),
      accepted_status_values = list("SUCCESS"),
      require_scale_repaired_qdesn_forecasts = TRUE
    )
  ),
  article_outputs = list(
    summary_csv = "tables/toy.csv",
    tex_wrapper = "tables/toy.tex",
    normal_tex = "tables/toy_normal.tex",
    laplace_tex = "tables/toy_laplace.tex",
    gausmix_tex = "tables/toy_gausmix.tex",
    manifest = "tables/toy_manifest.txt"
  ),
  article_policy = "toy final TT500 test"
)
app_write_yaml(final_config, final_config_path)
final_result <- app_validate_tt500_final_validation(final_config_path)
stopifnot(nrow(final_result$tt500) == 30L)

bad_final_config <- final_config
bad_final_config$interfaces$toy_qdesn$sha256 <- "wrong"
bad_final_config_path <- file.path(final_dir, "bad_final_hash.yaml")
app_write_yaml(bad_final_config, bad_final_config_path)
bad_hash_msg <- tryCatch({
  app_validate_tt500_final_validation(bad_final_config_path)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("SHA-256 mismatch", bad_hash_msg, fixed = TRUE))

bad_final_interface <- final_interface
bad_final_interface$forecast_lead[[30L]] <- 1L
app_write_csv(bad_final_interface, final_interface_path)
bad_final_config <- final_config
bad_final_config$interfaces$toy_qdesn$sha256 <- app_sha256_file(final_interface_path)
app_write_yaml(bad_final_config, bad_final_config_path)
bad_lead_msg <- tryCatch({
  app_validate_tt500_final_validation(bad_final_config_path)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("complete rolling-origin lead grid", bad_lead_msg, fixed = TRUE))

bad_final_interface <- final_interface
bad_final_interface$forecast_lead_metrics_path <- sub("_scale_repaired", "", bad_final_interface$forecast_lead_metrics_path, fixed = TRUE)
app_write_csv(bad_final_interface, final_interface_path)
bad_final_config$interfaces$toy_qdesn$sha256 <- app_sha256_file(final_interface_path)
app_write_yaml(bad_final_config, bad_final_config_path)
bad_scale_msg <- tryCatch({
  app_validate_tt500_final_validation(bad_final_config_path)
  NA_character_
}, error = function(e) conditionMessage(e))
stopifnot(grepl("scale-repaired", bad_scale_msg, fixed = TRUE))
