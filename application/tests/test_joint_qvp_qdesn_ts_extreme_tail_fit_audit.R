ts_extreme_tail_audit_dir <- tempfile("joint_qvp_ts_extreme_tail_audit_")
ts_extreme_tail_scenarios <- app_joint_qvp_default_ts_synthetic_scenarios()
ts_extreme_tail_scenarios <- ts_extreme_tail_scenarios[
  ts_extreme_tail_scenarios$case_id == "ts_asymmetric_laplace_tail",
  ,
  drop = FALSE
]
ts_extreme_tail_result <- app_joint_qvp_run_ts_extreme_tail_fit_audit(
  out_dir = ts_extreme_tail_audit_dir,
  scenarios = ts_extreme_tail_scenarios,
  vb_kappa_values = c(0.5, 1),
  mcmc_case_ids = character(),
  vb_max_iter = 180L
)

ts_extreme_tail_manifest <- utils::read.csv(
  file.path(ts_extreme_tail_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_ts_extreme_tail_labels <- c(
  "fit_diagnostics",
  "audit_summary",
  "check_loss_baseline",
  "audit_controls",
  "audit_report"
)
stopifnot(identical(ts_extreme_tail_manifest$label, expected_ts_extreme_tail_labels))
stopifnot(all(nchar(ts_extreme_tail_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_extreme_tail_manifest))) {
  artifact_path <- file.path(ts_extreme_tail_result$out_dir, ts_extreme_tail_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_extreme_tail_manifest$sha256[[ii]]))
}

ts_extreme_tail_summary <- utils::read.csv(
  file.path(ts_extreme_tail_result$out_dir, "audit_summary.csv"),
  stringsAsFactors = FALSE
)
qr_row <- ts_extreme_tail_summary[ts_extreme_tail_summary$fit == "check_loss_qr", , drop = FALSE]
vb_bad_row <- ts_extreme_tail_summary[ts_extreme_tail_summary$fit == "al_vb_kappa_0.5", , drop = FALSE]
vb_good_row <- ts_extreme_tail_summary[ts_extreme_tail_summary$fit == "al_vb_kappa_1", , drop = FALSE]
stopifnot(nrow(qr_row) == 1L)
stopifnot(nrow(vb_bad_row) == 1L)
stopifnot(nrow(vb_good_row) == 1L)
stopifnot(qr_row$max_tail_rmse_to_truth < 0.25)
stopifnot(vb_bad_row$max_tail_rmse_to_truth > 1)
stopifnot(vb_good_row$max_tail_rmse_to_truth < 0.35)
stopifnot(vb_good_row$max_tail_abs_hit_rate_error < 0.05)

ts_extreme_tail_diagnostics <- utils::read.csv(
  file.path(ts_extreme_tail_result$out_dir, "fit_diagnostics.csv"),
  stringsAsFactors = FALSE
)
vb_good_tail <- ts_extreme_tail_diagnostics[
  ts_extreme_tail_diagnostics$fit == "al_vb_kappa_1" &
    ts_extreme_tail_diagnostics$tau %in% c(0.1, 0.9),
  ,
  drop = FALSE
]
stopifnot(nrow(vb_good_tail) == 2L)
stopifnot(max(abs(vb_good_tail$hit_rate_minus_tau)) < 0.05)

ts_extreme_tail_report <- readLines(file.path(ts_extreme_tail_result$out_dir, "audit_report.md"), warn = FALSE)
stopifnot(any(grepl("kappa = 0.5", ts_extreme_tail_report, fixed = TRUE)))
stopifnot(any(grepl("kappa = 1", ts_extreme_tail_report, fixed = TRUE)))
