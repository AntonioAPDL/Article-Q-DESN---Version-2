local({
tmp_registry_dir <- file.path(
  "application",
  "runs",
  "local_audits",
  paste0("current_output_registry_test_", Sys.getpid())
)
app_ensure_dir(app_path(tmp_registry_dir, "tables"))
app_ensure_dir(app_path(tmp_registry_dir, "figures"))
on.exit(unlink(app_path(tmp_registry_dir), recursive = TRUE, force = TRUE), add = TRUE)

write.csv(
  data.frame(
    model_id = c("qdesn_latent_path_rhs_al_vb_test_p50", "raw_glofas_test_p50"),
    n_quantile_scores = c(28L, 28L),
    check_loss_mean = c(0.6, 0.8),
    interval_score_mean = c(3.2, 4.0),
    interval_coverage_mean = c(0.5, 0.0),
    crps_quantile_grid_mean = c(0.7, 1.0)
  ),
  app_path(tmp_registry_dir, "tables", "score.csv"),
  row.names = FALSE
)
write.csv(
  data.frame(
    model_id = c("qdesn_latent_path_rhs_al_vb_test_p50", "raw_glofas_test_p50"),
    model_family = c("qdesn_glofas_discrepancy", "raw_glofas"),
    mae_to_observation = c(1.2, 1.6),
    rmse_to_observation = c(1.4, 1.9),
    bias_to_observation = c(-1.1, -1.5)
  ),
  app_path(tmp_registry_dir, "tables", "metrics.csv"),
  row.names = FALSE
)
write.csv(
  data.frame(
    origin_date = "2022-12-25",
    n_forecast_window_rows = 28L,
    forecast_band_ok = TRUE
  ),
  app_path(tmp_registry_dir, "tables", "band.csv"),
  row.names = FALSE
)
write.csv(
  data.frame(
    fit_id = "qdesn_latent_path_rhs_al_vb_test_p50",
    vb_iterations = 17L
  ),
  app_path(tmp_registry_dir, "tables", "fit_diag.csv"),
  row.names = FALSE
)
write.csv(
  data.frame(
    candidate_id = "toy_candidate",
    reference_D = 1L,
    reference_n = "300",
    reference_n_tilde = "none",
    reference_m = 100L,
    reference_washout = 25L,
    reference_alpha = "0.92",
    reference_rho = "0.97",
    reference_pi_w = "0.03",
    reference_pi_in = "1",
    reference_win_scale_global = 0.2,
    reference_win_scale_bias = 0.25,
    reference_seed = 123L,
    discrepancy_D = 2L,
    discrepancy_n = "200;100",
    discrepancy_n_tilde = "100",
    discrepancy_m = 80L,
    discrepancy_washout = 25L,
    discrepancy_alpha = "0.1;0.2",
    discrepancy_rho = "0.9;0.8",
    discrepancy_pi_w = "0.03;0.04",
    discrepancy_pi_in = "1;1",
    discrepancy_win_scale_global = 0.15,
    discrepancy_win_scale_bias = 0.16,
    discrepancy_seed = 321L,
    shared_rhs_tau0 = 0.003,
    discrepancy_rhs_tau0 = 0.03,
    discrepancy_transition_strategy = "persistence_anchored_innovation"
  ),
  app_path(tmp_registry_dir, "tables", "model_spec.csv"),
  row.names = FALSE
)
write.csv(
  data.frame(
    candidate_id = "toy_candidate",
    window = "all",
    estimate_mode = "isotonic",
    n_dates = 12495L,
    crps_quantile_grid_mean = 0.0445,
    interval_coverage = 0.906
  ),
  app_path(tmp_registry_dir, "tables", "observed_history.csv"),
  row.names = FALSE
)
writeLines(
  c(
    "reservoir:",
    "  D: 1",
    "  'n': 300",
    "  n_tilde: []",
    "  m: 100",
    "  washout: 25",
    "  alpha: 0.92",
    "  rho: 0.97",
    "  seed: 123",
    "inference:",
    "  vb_ld:",
    "    rhs_tau0: 0.003",
    "    rhs_alpha_tau0: 0.03"
  ),
  app_path(tmp_registry_dir, "tables", "run_config.yaml")
)
writeLines("fake pdf", app_path(tmp_registry_dir, "figures", "paths.pdf"))
writeLines("fake pdf", app_path(tmp_registry_dir, "figures", "forecast.pdf"))
writeLines("fake pdf", app_path(tmp_registry_dir, "figures", "traces.pdf"))
write.csv(
  data.frame(
    enabled = TRUE,
    model_family = "qdesn_glofas_discrepancy",
    spread_calibration_factor = 1.4,
    spread_calibration_additive_width = 0.5,
    center_quantile = 0.5,
    calibration_id = "toy_spread",
    n_rows_calibrated = 28L
  ),
  app_path(tmp_registry_dir, "tables", "spread.csv"),
  row.names = FALSE
)

promotion_manifest <- data.frame(
  output_role = c(
    "score_summary_csv",
    "post_fit_metrics_by_model",
    "post_fit_forecast_window_band_check",
    "qdesn_discrepancy_fit_diagnostics",
    "run_config_yaml",
    "spread_calibration_manifest",
    "authoritative_model_spec",
    "observed_history_full7_ranking",
    "discrepancy_corrected_quantile_paths",
    "post_fit_test__forecast_window_pm30",
    "post_fit_test__diagnostic_traces"
  ),
  promoted_path = app_path(
    tmp_registry_dir,
    c(
      "tables/score.csv",
      "tables/metrics.csv",
      "tables/band.csv",
      "tables/fit_diag.csv",
      "tables/run_config.yaml",
      "tables/spread.csv",
      "tables/model_spec.csv",
      "tables/observed_history.csv",
      "figures/paths.pdf",
      "figures/forecast.pdf",
      "figures/traces.pdf"
    )
  ),
  run_id = "toy_run",
  config_path = app_path("application/config/toy.yaml"),
  article_git_sha = "article_sha",
  engine_repo_sha = "engine_sha",
  stringsAsFactors = FALSE
)
promotion_path <- app_path(tmp_registry_dir, "tables", "promotion_manifest.csv")
write.csv(promotion_manifest, promotion_path, row.names = FALSE)

result <- app_write_current_application_selection(
  promotion_manifest = promotion_path,
  registry_tex = file.path(tmp_registry_dir, "tables/current_outputs.tex"),
  score_tex = file.path(tmp_registry_dir, "tables/current_score.tex"),
  score_csv = file.path(tmp_registry_dir, "tables/current_score.csv"),
  selection_manifest = file.path(tmp_registry_dir, "tables/current_selection.csv"),
  quiet = TRUE
)

stopifnot(file.exists(app_path(tmp_registry_dir, "tables", "current_outputs.tex")))
stopifnot(file.exists(app_path(tmp_registry_dir, "tables", "current_score.tex")))
stopifnot(file.exists(app_path(tmp_registry_dir, "tables", "current_score.csv")))
stopifnot(file.exists(app_path(tmp_registry_dir, "tables", "current_selection.csv")))
stopifnot(identical(result$registry$run_id, "toy_run"))
stopifnot(identical(result$registry$qdesn_check_loss, "0.6000"))
stopifnot(identical(result$registry$raw_check_loss, "0.8000"))
stopifnot(identical(result$registry$check_loss_reduction, "25.0\\%"))
stopifnot(identical(result$registry$qdesn_interval_score, "3.2000"))
stopifnot(identical(result$registry$raw_interval_score, "4.0000"))
stopifnot(identical(result$registry$interval_score_reduction, "20.0\\%"))
stopifnot(identical(result$registry$qdesn_crps, "0.7000"))
stopifnot(identical(result$registry$raw_crps, "1.0000"))
stopifnot(identical(result$registry$crps_reduction, "30.0\\%"))
stopifnot(identical(result$registry$qdesn_mean_coverage, "0.500"))
stopifnot(identical(result$registry$raw_mean_coverage, "0.000"))
stopifnot(identical(result$registry$reservoir_depth, "1"))
stopifnot(identical(result$registry$reservoir_size, "300"))
stopifnot(identical(result$registry$reducer_size, "none"))
stopifnot(identical(result$registry$reservoir_washout, "25"))
stopifnot(identical(result$registry$reservoir_seed, "123"))
stopifnot(identical(result$registry$rhs_shared_tau0, "0.003"))
stopifnot(identical(result$registry$rhs_discrepancy_tau0, "0.03"))
stopifnot(identical(result$registry$candidate_id, "toy_candidate"))
stopifnot(identical(result$registry$discrepancy_transition_strategy, "persistence-anchored innovation"))
stopifnot(identical(result$registry$reference_reservoir_pi_w, "0.03"))
stopifnot(identical(result$registry$reference_reservoir_pi_in, "1"))
stopifnot(identical(result$registry$reference_reservoir_win_scale_global, "0.2"))
stopifnot(identical(result$registry$reference_reservoir_win_scale_bias, "0.25"))
stopifnot(identical(result$registry$discrepancy_reservoir_depth, "2"))
stopifnot(identical(result$registry$discrepancy_reservoir_size, "200,100"))
stopifnot(identical(result$registry$discrepancy_reducer_size, "100"))
stopifnot(identical(result$registry$discrepancy_reservoir_alpha, "0.1,0.2"))
stopifnot(identical(result$registry$discrepancy_reservoir_seed, "321"))
stopifnot(identical(result$registry$spread_calibration_enabled, "yes"))
stopifnot(identical(result$registry$spread_calibration_factor, "1.4"))
stopifnot(identical(result$registry$spread_calibration_additive_width, "0.5"))
stopifnot(identical(result$registry$spread_calibration_center_quantile, "0.50"))
stopifnot(identical(result$registry$spread_calibration_id, "toy_spread"))
stopifnot(grepl("additional spread calibration is applied before display", result$registry$spread_calibration_description, fixed = TRUE))
stopifnot(identical(result$registry$observed_history_crps, "0.0445"))
stopifnot(identical(result$registry$observed_history_coverage, "0.906"))
stopifnot(identical(result$registry$observed_history_dates, "12,495"))
registry_tex <- readLines(app_path(tmp_registry_dir, "tables", "current_outputs.tex"))
stopifnot(any(grepl("GlofasApplicationCurrentSharedRhsTau", registry_tex, fixed = TRUE)))
stopifnot(any(grepl("GlofasApplicationCurrentDiscrepancyRhsTau", registry_tex, fixed = TRUE)))
stopifnot(any(grepl("GlofasApplicationCurrentQdesnCrps", registry_tex, fixed = TRUE)))
stopifnot(any(grepl("GlofasApplicationCurrentSpreadCalibrationFactor", registry_tex, fixed = TRUE)))
stopifnot(any(grepl("GlofasApplicationCurrentReferenceReservoirDepth", registry_tex, fixed = TRUE)))
stopifnot(any(grepl("GlofasApplicationCurrentDiscrepancyReservoirDepth", registry_tex, fixed = TRUE)))
stopifnot(any(grepl("GlofasApplicationCurrentObservedHistoryCrps", registry_tex, fixed = TRUE)))
score_tex <- readLines(app_path(tmp_registry_dir, "tables", "current_score.tex"))
stopifnot(any(grepl("Q--DESN correction", score_tex, fixed = TRUE)))
stopifnot(any(grepl("Raw GloFAS", score_tex, fixed = TRUE)))
})
