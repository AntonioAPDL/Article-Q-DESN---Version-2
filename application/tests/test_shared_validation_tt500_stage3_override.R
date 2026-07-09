cfg <- app_read_yaml(app_default_tt500_final_validation_config())
override <- cfg$summary_overrides$qdesn_vb_stage3_forecast_bias_rescue
stopifnot(isTRUE(override$enabled))
stopifnot(identical(
  override$primary_profile,
  "tt500vb_f3_d1_n30_a0p02_r0p45_m15_lag15_rl0_pw0p03_pin0p3"
))
stopifnot(identical(
  override$validation_commit_at_export,
  "203f47adcbd417827e26e8efaf36f120e075fbf3"
))
stopifnot(identical(app_sha256_file(override$fit_forecast_summary_path), override$fit_forecast_summary_sha256))
stopifnot(identical(app_sha256_file(override$dominance_cell_summary_path), override$dominance_cell_summary_sha256))
stopifnot(identical(app_sha256_file(override$dominance_profile_ranking_path), override$dominance_profile_ranking_sha256))
stopifnot(identical(app_sha256_file(override$audit_summary_path), override$audit_summary_sha256))

audit <- app_read_csv(override$audit_summary_path)
stopifnot(nrow(audit) == 1L)
stopifnot(isTRUE(app_as_bool(audit$strict_ready[[1L]])))
stopifnot(isTRUE(app_as_bool(audit$generic_ranking_exists[[1L]])))
stopifnot(isTRUE(app_as_bool(audit$dominance_ranking_exists[[1L]])))
stopifnot(as.integer(audit$expected_roots[[1L]]) == 144L)
stopifnot(as.integer(audit$n_success[[1L]]) == 144L)
stopifnot(as.integer(audit$n_fail[[1L]]) == 0L)
stopifnot(as.integer(audit$forbidden_binary_count_total[[1L]]) == 0L)

rank <- app_read_csv(override$dominance_profile_ranking_path)
primary <- rank[rank$screening_profile_base == override$primary_profile, , drop = FALSE]
stopifnot(nrow(primary) == 1L)
stopifnot(isTRUE(app_as_bool(primary$dominance_pass[[1L]])))
stopifnot(as.integer(primary$n_cells[[1L]]) == 3L)
stopifnot(as.integer(primary$n_cells_beating_all_primary[[1L]]) == 3L)

summary <- app_read_csv(app_path("tables/qdesn_validation_tt500_final_summary.csv"))
promoted <- summary[
  summary$article_interface_ids == "qdesn_vb_stage3_forecast_bias_rescue" &
    summary$model_key == "qdesn_exal_rhs_ns" &
    summary$inference == "vb",
  ,
  drop = FALSE
]
stopifnot(nrow(promoted) == 3L)
stopifnot(identical(sort(paste(promoted$family, sprintf("%.2f", promoted$tau))), c(
  "gausmix 0.25",
  "normal 0.25",
  "normal 0.50"
)))
stopifnot(all(promoted$validation_commit == override$validation_commit_at_export))
stopifnot(all(promoted$forecast_qtrue_mae_lead_weighted < 2.4))
stopifnot(all(promoted$forecast_pinball_mean_lead_weighted < 4.6))
stopifnot(all(promoted$runtime_hours < 0.002))

manifest <- readLines(app_path("tables/qdesn_validation_tt500_final_manifest.txt"), warn = FALSE)
stopifnot(any(grepl("Summary override rows applied:", manifest, fixed = TRUE)))
stopifnot(any(grepl("qdesn_vb_stage3_forecast_bias_rescue", manifest, fixed = TRUE)))
stopifnot(any(grepl(override$primary_profile, manifest, fixed = TRUE)))
