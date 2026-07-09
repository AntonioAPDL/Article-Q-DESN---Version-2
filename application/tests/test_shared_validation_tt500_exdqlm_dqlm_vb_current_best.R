cfg <- app_read_yaml(app_default_tt500_final_validation_config())
override <- cfg$summary_overrides$exdqlm_dqlm_vb_current_best_c13

stopifnot(isTRUE(override$enabled))
stopifnot(identical(override$override_type, "exdqlm_dqlm_vb_current_best"))
stopifnot(identical(
  override$validation_commit_at_export,
  "10ef52920b8d77de9c01d05efd0db2939c70f4e6"
))
stopifnot(identical(
  override$validation_audit_commit,
  "fc2bfefd814a3325eea957bd6f439439a8a6dd4d"
))
stopifnot(identical(
  override$selected_candidate_id,
  "c13_trend100_season1_df0995s099"
))
stopifnot(identical(app_sha256_file(override$current_best_csv_path), override$current_best_csv_sha256))
stopifnot(identical(app_sha256_file(override$current_best_audit_path), override$current_best_audit_sha256))
stopifnot(identical(app_sha256_file(override$raw_interface_path), override$raw_interface_sha256))

current_best <- app_read_csv(override$current_best_csv_path)
stopifnot(nrow(current_best) == as.integer(override$expected_cells))
stopifnot(all(current_best$candidate_id == override$selected_candidate_id))
stopifnot(all(current_best$validation_commit == override$validation_commit_at_export))
stopifnot(all(current_best$validation_branch == cfg$validation_branch))
stopifnot(all(current_best$source_registry_hash_value == cfg$source_registry_hash_value))
stopifnot(all(as.integer(current_best$n_leads) == as.integer(override$expected_leads)))
stopifnot(all(as.integer(current_best$n_origins_scored_total) == as.integer(override$expected_origins_scored_total)))

summary <- app_read_csv(app_path("tables/qdesn_validation_tt500_final_summary.csv"))
promoted <- summary[
  summary$model_family == "exdqlm_dqlm" &
    summary$inference == "vb",
  ,
  drop = FALSE
]
stopifnot(nrow(promoted) == 18L)
stopifnot(all(promoted$article_interface_ids == "exdqlm_dqlm_vb_current_best_c13"))
stopifnot(all(promoted$validation_commit == override$validation_commit_at_export))
stopifnot(all(grepl(override$current_best_csv_sha256, promoted$article_interface_sha256, fixed = TRUE)))
stopifnot(all(grepl(override$current_best_audit_sha256, promoted$article_interface_sha256, fixed = TRUE)))
stopifnot(all(grepl(override$raw_interface_sha256, promoted$article_interface_sha256, fixed = TRUE)))

for (ii in seq_len(nrow(current_best))) {
  row <- current_best[ii, , drop = FALSE]
  got <- promoted[
    promoted$model_key == row$model_variant[[1L]] &
      promoted$family == row$family[[1L]] &
      abs(as.numeric(promoted$tau) - as.numeric(row$tau[[1L]])) < 1.0e-12,
    ,
    drop = FALSE
  ]
  stopifnot(nrow(got) == 1L)
  stopifnot(abs(got$fit_qtrue_rmse[[1L]] - row$fit_qtrue_rmse[[1L]]) < 1.0e-10)
  stopifnot(abs(got$fit_pinball_mean[[1L]] - row$fit_check[[1L]]) < 1.0e-10)
  stopifnot(abs(got$forecast_qtrue_mae_lead_weighted[[1L]] - row$forecast_qtrue_mae[[1L]]) < 1.0e-10)
  stopifnot(abs(got$forecast_qtrue_rmse_lead_weighted[[1L]] - row$forecast_qtrue_rmse[[1L]]) < 1.0e-10)
  stopifnot(abs(got$forecast_pinball_mean_lead_weighted[[1L]] - row$forecast_check[[1L]]) < 1.0e-10)
}

manifest <- readLines(app_path("tables/qdesn_validation_tt500_final_manifest.txt"), warn = FALSE)
stopifnot(any(grepl("exdqlm_dqlm_vb_current_best_c13", manifest, fixed = TRUE)))
stopifnot(any(grepl(override$current_best_csv_sha256, manifest, fixed = TRUE)))
stopifnot(any(grepl(override$current_best_audit_sha256, manifest, fixed = TRUE)))
