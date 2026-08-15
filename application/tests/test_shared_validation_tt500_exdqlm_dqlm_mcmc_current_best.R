cfg <- app_read_yaml(app_default_tt500_final_validation_config())
override_id <- "exdqlm_dqlm_c13_mcmc_current_best_20260704"
override <- cfg$summary_overrides[[override_id]]

stopifnot(isTRUE(override$enabled))
stopifnot(identical(override$override_type, "exdqlm_dqlm_mcmc_current_best"))
stopifnot(identical(
  override$validation_commit_at_export,
  "49a4caa5b62d32216e75945e8adfbfa8e83c63cc"
))
stopifnot(identical(
  override$validation_run_commit,
  "49a4caa5b62d32216e75945e8adfbfa8e83c63cc"
))
stopifnot(identical(
  override$run_tag,
  "20260704_exdqlm_dqlm_c13_mcmc_500obs_full_v2"
))
stopifnot(identical(
  override$promotion_id,
  "exdqlm_dqlm_c13_mcmc_500obs_authoritative_20260704"
))
stopifnot(identical(
  override$selected_candidate_id,
  "c13_trend100_season1_df0995s099"
))
stopifnot(identical(app_sha256_file(override$promotion_summary_path), override$promotion_summary_sha256))
stopifnot(identical(app_sha256_file(override$promotion_manifest_path), override$promotion_manifest_sha256))
stopifnot(identical(app_sha256_file(override$promotion_sources_path), override$promotion_sources_sha256))

promotion <- app_read_csv(override$promotion_summary_path)
stopifnot(nrow(promotion) == as.integer(override$expected_cells))
stopifnot(all(promotion$promotion_id == override$promotion_id))
stopifnot(all(promotion$promotion_status == override$promotion_status))
stopifnot(all(promotion$diagnostic_qualification == override$diagnostic_qualification))
stopifnot(all(promotion$model_family == "exdqlm_dqlm"))
stopifnot(identical(sort(unique(promotion$model_variant)), sort(as.character(unlist(override$expected_model_variants)))))
stopifnot(identical(sort(unique(promotion$family)), sort(as.character(unlist(override$expected_families)))))
stopifnot(identical(sort(unique(as.numeric(promotion$tau))), sort(as.numeric(unlist(override$expected_tau_values)))))
stopifnot(all(promotion$inference == "mcmc"))
stopifnot(all(promotion$method == "mcmc"))
stopifnot(all(promotion$candidate_id == override$selected_candidate_id))
stopifnot(all(promotion$status == "done"))
stopifnot(all(promotion$health_gate == "PASS"))
stopifnot(all(as.logical(promotion$comparison_eligible)))
stopifnot(all(as.integer(promotion$fit_size) == cfg$fit_size))
stopifnot(all(as.integer(promotion$effective_fit_size) == cfg$fit_size))
stopifnot(all(as.integer(promotion$n_leads) == as.integer(override$expected_leads)))
stopifnot(all(as.integer(promotion$n_origins_scored_total) == as.integer(override$expected_origins_scored_total)))
stopifnot(all(promotion$source_registry_hash_value == cfg$source_registry_hash_value))
stopifnot(all(promotion$validation_branch == cfg$validation_branch))
stopifnot(all(promotion$validation_commit_at_materialization == override$validation_commit_at_export))
stopifnot(all(promotion$validation_run_commit == override$validation_run_commit))
stopifnot(all(promotion$run_tag == override$run_tag))
stopifnot(!any(promotion$run_tag %in% as.character(unlist(override$invalid_run_tags))))

summary <- app_read_csv(app_path("tables/qdesn_validation_tt500_final_summary.csv"))
promoted <- summary[
  summary$model_family == "exdqlm_dqlm" &
    summary$inference == "mcmc",
  ,
  drop = FALSE
]
stopifnot(nrow(promoted) == 18L)
stopifnot(all(promoted$article_interface_ids == override_id))
stopifnot(all(promoted$validation_commit == override$validation_commit_at_export))
stopifnot(all(promoted$article_interface_sha256 == paste(
  c(override$promotion_summary_sha256, override$promotion_manifest_sha256, override$promotion_sources_sha256),
  collapse = ";"
)))
stopifnot(!any(promoted$article_interface_ids == "exdqlm_dqlm"))
stopifnot(!any(promoted$validation_commit == "d075941313186b15853e94c2a2cad7d0fec410d8"))

metric_pairs <- c(
  fit_qtrue_rmse = "fit_qtrue_rmse",
  fit_pinball_mean = "fit_check_loss",
  forecast_qtrue_mae_lead_weighted = "forecast_qtrue_mae_lead_weighted",
  forecast_qtrue_rmse_lead_weighted = "forecast_qtrue_rmse_lead_weighted",
  forecast_pinball_mean_lead_weighted = "forecast_check_loss_lead_weighted"
)
for (ii in seq_len(nrow(promotion))) {
  row <- promotion[ii, , drop = FALSE]
  got <- promoted[
    promoted$model_key == row$model_variant[[1L]] &
      promoted$family == row$family[[1L]] &
      abs(as.numeric(promoted$tau) - as.numeric(row$tau[[1L]])) < 1.0e-12,
    ,
    drop = FALSE
  ]
  stopifnot(nrow(got) == 1L)
  for (article_metric in names(metric_pairs)) {
    source_metric <- metric_pairs[[article_metric]]
    stopifnot(abs(as.numeric(got[[article_metric]][[1L]]) - as.numeric(row[[source_metric]][[1L]])) < 1.0e-10)
  }
}

manifest <- readLines(app_path("tables/qdesn_validation_tt500_final_manifest.txt"), warn = FALSE)
stopifnot(any(grepl(override_id, manifest, fixed = TRUE)))
stopifnot(any(grepl(override$run_tag, manifest, fixed = TRUE)))
stopifnot(any(grepl(override$promotion_summary_sha256, manifest, fixed = TRUE)))
stopifnot(any(grepl(override$promotion_manifest_sha256, manifest, fixed = TRUE)))
stopifnot(any(grepl(override$promotion_sources_sha256, manifest, fixed = TRUE)))
for (tag in as.character(unlist(override$invalid_run_tags))) {
  stopifnot(!any(grepl(tag, manifest, fixed = TRUE)))
}
