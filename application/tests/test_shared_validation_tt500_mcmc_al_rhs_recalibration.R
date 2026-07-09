cfg <- app_read_yaml(app_default_tt500_final_validation_config())
override <- cfg$summary_overrides$qdesn_mcmc_al_rhs_recalibrated_authoritative

stopifnot(isTRUE(override$enabled))
stopifnot(identical(override$override_type, "promotion_handoff"))
stopifnot(identical(
  override$validation_commit_at_export,
  "9819010fe658e8d71aef5a9c962a2a477a509b4c"
))
stopifnot(identical(
  override$promotion_id,
  "qdesn_tt500_mcmc_al_rhs_recalibrated_authoritative_20260702"
))
stopifnot(identical(
  override$diagnostic_qualification,
  "diagnostic_qualified_authoritative_mcmc_al_rhs_recalibrated"
))
stopifnot(identical(app_sha256_file(override$promotion_summary_path), override$promotion_summary_sha256))
stopifnot(identical(app_sha256_file(override$promotion_manifest_path), override$promotion_manifest_sha256))
stopifnot(identical(sort(as.character(unlist(override$accepted_signoff_grades))), c("PASS", "WARN")))

promotion <- app_read_csv(override$promotion_summary_path)
stopifnot(nrow(promotion) == 9L)
stopifnot(all(promotion$promotion_id == override$promotion_id))
stopifnot(all(promotion$diagnostic_qualification == override$diagnostic_qualification))
stopifnot(all(promotion$model_key == "qdesn_al_rhs_ns"))
stopifnot(all(promotion$qdesn_likelihood == "al"))
stopifnot(all(promotion$likelihood_family == "al"))
stopifnot(all(promotion$prior == "rhs_ns"))
stopifnot(all(promotion$method == "mcmc"))
stopifnot(all(promotion$inference == "mcmc"))
stopifnot(all(promotion$status == "SUCCESS"))
stopifnot(all(promotion$signoff_grade %in% c("PASS", "WARN")))
stopifnot(all(as.logical(promotion$comparison_eligible)))
stopifnot(all(as.integer(promotion$n_leads) == cfg$max_lead_configured))
stopifnot(all(as.integer(promotion$n_origins_scored_total) == 1000L))
stopifnot(all(as.integer(promotion$forecast_origin_stride) == cfg$origin_stride))
stopifnot(all(promotion$forecast_protocol == cfg$forecast_protocol))
stopifnot(all(promotion$source_registry_hash_value == cfg$source_registry_hash_value))
stopifnot(max(promotion$forecast_qtrue_mae_lead_weighted) < 13)
stopifnot(max(promotion$forecast_pinball_mean_lead_weighted) < 6)

summary <- app_read_csv(app_path("tables/qdesn_validation_tt500_final_summary.csv"))
promoted <- summary[
  summary$article_interface_ids == "qdesn_mcmc_al_rhs_recalibrated_authoritative" &
    summary$model_key == "qdesn_al_rhs_ns" &
    summary$inference == "mcmc",
  ,
  drop = FALSE
]
stopifnot(nrow(promoted) == 9L)
stopifnot(identical(sort(paste(promoted$family, sprintf("%.2f", promoted$tau))), sort(paste(promotion$family, sprintf("%.2f", promotion$tau)))))
stopifnot(all(promoted$validation_commit == override$validation_commit_at_export))
stopifnot(all(promoted$article_interface_sha256 == paste(c(override$promotion_summary_sha256, override$promotion_manifest_sha256), collapse = ";")))

old_al_rhs_mcmc <- summary[
  summary$article_interface_ids == "qdesn_mcmc" &
    summary$model_key == "qdesn_al_rhs_ns" &
    summary$inference == "mcmc",
  ,
  drop = FALSE
]
stopifnot(nrow(old_al_rhs_mcmc) == 0L)

metric_cols <- c(
  "fit_qtrue_rmse", "fit_pinball_mean",
  "forecast_qtrue_mae_lead_weighted", "forecast_qtrue_rmse_lead_weighted",
  "forecast_pinball_mean_lead_weighted"
)
for (ii in seq_len(nrow(promoted))) {
  row <- promoted[ii, , drop = FALSE]
  source <- promotion[
    promotion$family == row$family[[1L]] &
      abs(as.numeric(promotion$tau) - as.numeric(row$tau[[1L]])) < 1.0e-12,
    ,
    drop = FALSE
  ]
  stopifnot(nrow(source) == 1L)
  for (metric in metric_cols) {
    stopifnot(abs(as.numeric(row[[metric]][[1L]]) - as.numeric(source[[metric]][[1L]])) < 1.0e-10)
  }
}

manifest <- readLines(app_path("tables/qdesn_validation_tt500_final_manifest.txt"), warn = FALSE)
stopifnot(any(grepl("qdesn_mcmc_al_rhs_recalibrated_authoritative", manifest, fixed = TRUE)))
stopifnot(any(grepl(override$promotion_summary_sha256, manifest, fixed = TRUE)))
stopifnot(any(grepl(override$promotion_manifest_sha256, manifest, fixed = TRUE)))
stopifnot(any(grepl("replacement_signoff_grade: WARN", manifest, fixed = TRUE)))
