tmp_root <- tempfile("qdesn_launch_")
tmp_runs <- file.path(tmp_root, "runs")
dir.create(tmp_runs, recursive = TRUE)

tmp_cfg <- cfg
tmp_cfg$paths$runs <- tmp_runs
tmp_cfg$paths$input_manifest <- file.path(tmp_root, "input_manifest.csv")
tmp_cfg$dependencies$fail_if_qdesn_engine_missing <- FALSE
tmp_cfg$execution$prelaunch <- list(enabled = TRUE, purpose = "test")
run_dirs <- app_create_run_dirs(tmp_cfg, run_id = "test_prelaunch_dryrun")

reference_path <- file.path(tmp_root, "reference_gauge.csv")
retrospective_path <- file.path(tmp_root, "glofas_retrospective.csv")
ensemble_path <- file.path(tmp_root, "glofas_ensemble.csv")
app_write_csv(
  data.frame(
    date = as.Date("2026-01-01"),
    station_id = "toy",
    streamflow = 1,
    stringsAsFactors = FALSE
  ),
  reference_path
)
app_write_csv(
  data.frame(
    date = as.Date("2026-01-01"),
    location_id = "toy",
    glofas_streamflow = 1,
    stringsAsFactors = FALSE
  ),
  retrospective_path
)
app_write_csv(
  data.frame(
    origin_date = as.Date("2026-01-01"),
    target_date = as.Date("2026-01-02"),
    horizon = 1L,
    member = 1L,
    glofas_streamflow = 1,
    stringsAsFactors = FALSE
  ),
  ensemble_path
)
app_write_csv(
  data.frame(
    input_id = c("reference_gauge", "glofas_retrospective", "glofas_ensemble"),
    source_name = c("Toy reference gauge", "Toy GloFAS retrospective", "Toy GloFAS ensemble"),
    source_type = c("observation", "forecast_system", "forecast_system"),
    local_path = c(reference_path, retrospective_path, ensemble_path),
    upstream_reference = "toy",
    date_min = c("2026-01-01", "2026-01-01", "2026-01-01"),
    date_max = c("2026-01-01", "2026-01-01", "2026-01-02"),
    cutoff_date = "",
    row_count = 1L,
    column_count = c(3L, 3L, 5L),
    sha256 = c(app_sha256_file(reference_path), app_sha256_file(retrospective_path), app_sha256_file(ensemble_path)),
    created_at = "2026-05-11 00:00:00 EDT",
    notes = "self-contained launch-readiness test fixture",
    stringsAsFactors = FALSE
  ),
  tmp_cfg$paths$input_manifest
)

for (stage in app_launch_status_files()) {
  app_write_csv(
    data.frame(
      stage = stage,
      status = "completed",
      time = "2026-05-11 00:00:00 EDT",
      message = "",
      stringsAsFactors = FALSE
    ),
    file.path(run_dirs$logs, paste0(stage, "_status.csv"))
  )
}

fig_path <- file.path(run_dirs$figures, "toy_input_diagnostic.pdf")
app_ensure_dir(dirname(fig_path))
writeBin(as.raw(rep(1L, 200L)), fig_path)
app_write_csv(
  data.frame(
    figure_id = "toy",
    output_path = fig_path,
    source_script = "test_launch_readiness.R",
    run_id = "test_prelaunch_dryrun",
    input_manifest = "toy",
    panel_hash = "toy",
    config_path = "toy",
    git_sha = "toy",
    created_at = "2026-05-11 00:00:00 EDT",
    notes = "",
    stringsAsFactors = FALSE
  ),
  file.path(run_dirs$tables, "figure_manifest.csv")
)

pred <- data.frame(
  fit_id = c("raw", "disc"),
  model_id = c("raw_glofas", "qdesn_discrepancy_rhs_al_mcmc"),
  model_family = c("raw_glofas", "qdesn_glofas_discrepancy"),
  quantile_level = c(0.5, 0.5),
  qhat = c(1.0, 1.1),
  y_reference = c(1.2, 1.2),
  q_g_hat = c(1.0, 1.0),
  d_g_hat = c(NA, -0.1),
  raw_glofas_quantile = c(1.0, 1.0),
  discrepancy_hat = c(NA, -0.1),
  prediction_contract = c("raw_glofas_ensemble_quantile", "pilot_origin_state_glofas_quantile_minus_discrepancy"),
  contract_version = c("0.2", "0.2"),
  forecast_scope = c("issued_glofas_only", "issued_glofas_only"),
  q_g_source = c("ensemble_empirical_quantile", "ensemble_empirical_quantile"),
  discrepancy_feature_strategy = c("none", "origin_state_pilot"),
  prediction_unit = c("raw_point_baseline", "point_bridge"),
  posterior_draw_contract = c("not_applicable", "q_y_draw_equals_q_g_draw_minus_d_g_draw"),
  posterior_predictive_sampling = c("not_applicable", "disabled"),
  beyond_issued_horizon = c("disabled", "disabled"),
  discrepancy_feature_date = as.Date(c(NA, "2026-01-01")),
  origin_date = as.Date(c("2026-01-01", "2026-01-01")),
  target_date = as.Date(c("2026-01-02", "2026-01-02")),
  horizon = c(1L, 1L),
  stringsAsFactors = FALSE
)
app_write_csv(pred, file.path(run_dirs$tables, "prediction_quantiles.csv"))
app_write_csv(
  data.frame(
    model_id = c("raw_glofas", "qdesn_discrepancy_rhs_al_mcmc"),
    n_quantile_scores = c(1L, 1L),
    check_loss_mean = c(0.1, 0.05),
    interval_score_mean = c(NA_real_, NA_real_),
    interval_coverage_mean = c(NA_real_, NA_real_),
    crps_quantile_grid_mean = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  ),
  file.path(run_dirs$tables, "score_summary.csv")
)
app_write_csv(
  data.frame(
    fit_id = c("raw", "disc"),
    model_id = c("raw_glofas", "qdesn_discrepancy_rhs_al_mcmc"),
    model_family = c("raw_glofas", "qdesn_glofas_discrepancy"),
    quantile_level = c(0.5, 0.5),
    inference_method = c("none", "mcmc"),
    coefficient_prior = c("none", "rhs"),
    required = c(TRUE, TRUE),
    status = c("completed", "completed"),
    message = c("", "fit completed"),
    runtime_seconds = c(0.1, 0.2),
    stringsAsFactors = FALSE
  ),
  file.path(run_dirs$tables, "fit_status.csv")
)
for (path in c(
  "input_manifest_used.csv",
  "model_grid_used.csv",
  "quantile_grid_used.csv",
  "run_config.yaml",
  "git_state.txt",
  "session_info.txt"
)) {
  writeLines("toy", file.path(run_dirs$manifest, path))
}

stage_report <- app_launch_stage_checks(run_dirs)
stopifnot(nrow(stage_report) == length(app_launch_status_files()))
stopifnot(all(stage_report$status == "ok"))

figure_report <- app_launch_figure_checks(run_dirs, min_size_bytes = 10L, check_pdf_pages = FALSE)
stopifnot(all(figure_report$status == "ok"))

prediction_report <- app_launch_prediction_checks(run_dirs)
stopifnot(all(prediction_report$status == "ok"))

tmp_final_cfg <- tmp_cfg
tmp_final_cfg$execution$prelaunch <- list(enabled = FALSE)
tmp_final_cfg$execution$final_launch <- list(enabled = TRUE)
final_prediction_report <- app_launch_prediction_checks(run_dirs, cfg = tmp_final_cfg)
stopifnot(any(final_prediction_report$check == "prediction_contract_valid"))
stopifnot(any(final_prediction_report$status[final_prediction_report$check == "prediction_contract_valid"] == "failed"))
stopifnot(any(final_prediction_report$check == "posterior_draw_table_exists"))
stopifnot(any(final_prediction_report$status[final_prediction_report$check == "posterior_draw_table_exists"] == "failed"))

full_report <- app_check_launch_readiness(
  tmp_cfg,
  run_id = "test_prelaunch_dryrun",
  control = list(check_git = FALSE, check_pdf_pages = FALSE, min_figure_size_bytes = 10L)
)
stopifnot(any(full_report$check == "not_final_launch"))
stopifnot(all(full_report$status[full_report$required] == "ok"))

failed <- app_write_launch_readiness(full_report, run_dirs)
stopifnot(nrow(failed) == 0L)
stopifnot(file.exists(file.path(run_dirs$tables, "launch_readiness_report.csv")))
stopifnot(file.exists(file.path(run_dirs$tables, "launch_readiness_summary.txt")))
