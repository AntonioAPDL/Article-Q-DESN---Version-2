summary <- app_read_csv(app_path("tables/qdesn_validation_tt500_final_summary.csv"))
audit_path <- app_path("tables/qdesn_validation_tt500_vb_competitiveness_audit.csv")
stopifnot(file.exists(audit_path))
audit <- app_read_csv(audit_path)

metrics <- c(
  "fit_qtrue_rmse",
  "fit_pinball_mean",
  "forecast_qtrue_mae_lead_weighted",
  "forecast_pinball_mean_lead_weighted"
)
ratio_cols <- c(
  "ratio_fit_qtrue_rmse",
  "ratio_fit_pinball_mean",
  "ratio_forecast_qtrue_mae_lead_weighted",
  "ratio_forecast_pinball_mean_lead_weighted"
)

qdesn <- summary[
  summary$inference == "vb" &
    summary$model_family == "qdesn" &
    summary$model_key == "qdesn_exal_rhs_ns" &
    summary$qdesn_likelihood == "exal",
  ,
  drop = FALSE
]
baselines <- summary[
  summary$inference == "vb" &
    summary$model_family == "exdqlm_dqlm",
  ,
  drop = FALSE
]

stopifnot(nrow(qdesn) == 9L)
stopifnot(nrow(baselines) == 18L)
stopifnot(nrow(audit) == 9L)
stopifnot(all(is.finite(as.numeric(unlist(audit[ratio_cols], use.names = FALSE)))))
stopifnot(sum(audit$beats_best_dqlm_exdqlm_vb_all_four) >= 0L)
stopifnot(sum(audit$beats_best_dqlm_exdqlm_vb_all_four) <= nrow(audit))
stopifnot(sum(!audit$beats_best_dqlm_exdqlm_vb_all_four) >= 1L)
stopifnot(identical(sort(paste(qdesn$family, sprintf("%.2f", qdesn$tau))), sort(paste(audit$family, sprintf("%.2f", audit$tau)))))
stopifnot(all(baselines$article_interface_ids == "exdqlm_dqlm_vb_current_best_c13"))
stopifnot(all(grepl("540588b9588b5c9b062e897d3d396984faa0d4edeb80ec10698097ac78ef6b47", baselines$article_interface_sha256, fixed = TRUE)))

for (ii in seq_len(nrow(qdesn))) {
  row <- qdesn[ii, , drop = FALSE]
  base <- baselines[
    baselines$family == row$family[[1L]] &
      abs(as.numeric(baselines$tau) - as.numeric(row$tau[[1L]])) < 1.0e-12,
    ,
    drop = FALSE
  ]
  stopifnot(nrow(base) == 2L)
  for (metric in metrics) {
    stopifnot(is.finite(as.numeric(row[[metric]][[1L]])))
    stopifnot(all(is.finite(as.numeric(base[[metric]]))))
  }
}
