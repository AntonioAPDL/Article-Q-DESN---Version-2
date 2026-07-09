cfg <- app_read_yaml(app_default_tt500_final_validation_config())
override <- cfg$summary_overrides$qdesn_vb_stage4_remaining_cell_repair
as_bool_vec <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  tolower(as.character(x)) %in% c("true", "t", "1", "yes")
}

stopifnot(isTRUE(override$enabled))
stopifnot(identical(override$override_type, "candidate_ledger"))
stopifnot(identical(
  override$validation_commit_at_export,
  "4d77027184df369a0607f3ac78eb7eae2687a5ed"
))
stopifnot(identical(app_sha256_file(override$candidate_ledger_path), override$candidate_ledger_sha256))
stopifnot(identical(app_sha256_file(override$candidate_ledger_manifest_path), override$candidate_ledger_manifest_sha256))
stopifnot(identical(sort(as.character(unlist(override$accepted_signoff_grades))), c("PASS", "WARN")))

for (stage in names(override$stage_sources)) {
  src <- override$stage_sources[[stage]]
  stopifnot(identical(app_sha256_file(src$fit_forecast_summary_path), src$fit_forecast_summary_sha256))
  stopifnot(identical(app_sha256_file(src$dominance_cell_summary_path), src$dominance_cell_summary_sha256))
  stopifnot(identical(app_sha256_file(src$dominance_profile_ranking_path), src$dominance_profile_ranking_sha256))
  stopifnot(identical(app_sha256_file(src$audit_summary_path), src$audit_summary_sha256))
  audit <- app_read_csv(src$audit_summary_path)
  stopifnot(nrow(audit) == 1L)
  stopifnot(isTRUE(app_as_bool(audit$strict_ready[[1L]])))
  stopifnot(as.integer(audit$n_success[[1L]]) == as.integer(audit$expected_roots[[1L]]))
  stopifnot(as.integer(audit$n_fail[[1L]]) == 0L)
  stopifnot(as.integer(audit$forbidden_binary_count_total[[1L]]) == 0L)
}

ledger <- app_read_csv(override$candidate_ledger_path)
expected_cells <- c(
  "gausmix 0.05",
  "gausmix 0.50",
  "laplace 0.05",
  "laplace 0.25",
  "laplace 0.50",
  "normal 0.05"
)
stopifnot(nrow(ledger) == 6L)
stopifnot(identical(sort(paste(ledger$family, sprintf("%.2f", ledger$tau))), sort(expected_cells)))
stopifnot(all(as_bool_vec(ledger$beats_all_primary_baselines)))
stopifnot(all(as_bool_vec(ledger$stage_strict_ready)))
stopifnot(all(as.integer(ledger$stage_n_fail) == 0L))
stopifnot(all(as.integer(ledger$stage_forbidden_binary_count_total) == 0L))
ratio_cols <- c(
  "forecast_mae_ratio_vs_best_vb_baseline",
  "forecast_pinball_ratio_vs_best_vb_baseline",
  "fit_rmse_ratio_vs_best_vb_baseline",
  "fit_pinball_ratio_vs_best_vb_baseline"
)
stopifnot(all(as.numeric(unlist(ledger[ratio_cols], use.names = FALSE)) < 1))

summary <- app_read_csv(app_path("tables/qdesn_validation_tt500_final_summary.csv"))
promoted <- summary[
  summary$article_interface_ids == "qdesn_vb_stage4_remaining_cell_repair" &
    summary$model_key == "qdesn_exal_rhs_ns" &
    summary$inference == "vb",
  ,
  drop = FALSE
]
stopifnot(nrow(promoted) == 6L)
stopifnot(identical(sort(paste(promoted$family, sprintf("%.2f", promoted$tau))), sort(expected_cells)))
stopifnot(all(promoted$validation_commit == override$validation_commit_at_export))

for (ii in seq_len(nrow(promoted))) {
  row <- promoted[ii, , drop = FALSE]
  base <- summary[
    summary$model_family == "exdqlm_dqlm" &
      summary$inference == "vb" &
      summary$family == row$family[[1L]] &
      abs(as.numeric(summary$tau) - as.numeric(row$tau[[1L]])) < 1.0e-12,
    ,
    drop = FALSE
  ]
  stopifnot(nrow(base) == 2L)
  stopifnot(all(is.finite(as.numeric(unlist(row[, c(
    "fit_qtrue_rmse", "fit_pinball_mean",
    "forecast_qtrue_mae_lead_weighted",
    "forecast_pinball_mean_lead_weighted"
  )], use.names = FALSE)))))
  stopifnot(all(is.finite(as.numeric(unlist(base[, c(
    "fit_qtrue_rmse", "fit_pinball_mean",
    "forecast_qtrue_mae_lead_weighted",
    "forecast_pinball_mean_lead_weighted"
  )], use.names = FALSE)))))
}

manifest <- readLines(app_path("tables/qdesn_validation_tt500_final_manifest.txt"), warn = FALSE)
stopifnot(any(grepl("Summary override rows applied:", manifest, fixed = TRUE)))
stopifnot(any(grepl("qdesn_vb_stage4_remaining_cell_repair", manifest, fixed = TRUE)))
stopifnot(any(grepl(override$candidate_ledger_sha256, manifest, fixed = TRUE)))
stopifnot(any(grepl("replacement_signoff_grade: WARN", manifest, fixed = TRUE)))
stopifnot(any(grepl("replacement_signoff_reason: vb_converged_false", manifest, fixed = TRUE)))
