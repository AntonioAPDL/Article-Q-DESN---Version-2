ts_vb_conv_cal_dir <- tempfile("joint_qvp_ts_vb_conv_cal_")
dir.create(ts_vb_conv_cal_dir, recursive = TRUE, showWarnings = FALSE)
ts_vb_conv_scenario <- app_joint_qvp_default_ts_synthetic_scenarios()[1, , drop = FALSE]
ts_vb_conv_scenario$case_id <- paste0(ts_vb_conv_scenario$case_id, "_rep01_seed20260701")
ts_vb_conv_scenario$base_case_id <- "ts_student_t_lscale"
ts_vb_conv_scenario$replicate_id <- 1L
ts_vb_conv_scenario$Tn <- 18L
ts_vb_conv_scenario$kappa <- 1
ts_vb_conv_scenario$tau0 <- 1
ts_vb_conv_scenario$a_sigma <- 2
ts_vb_conv_scenario$b_sigma <- 1
ts_vb_conv_scenario$alpha_prior_mean <- "empirical_quantile"
ts_vb_conv_scenario$alpha_prior_sd <- 1
ts_vb_conv_scenario$rhs_vb_inner <- 5L
utils::write.csv(
  ts_vb_conv_scenario,
  file.path(ts_vb_conv_cal_dir, "replicated_run_config.csv"),
  row.names = FALSE
)
utils::write.csv(
  data.frame(
    case_id = ts_vb_conv_scenario$case_id,
    base_case_id = ts_vb_conv_scenario$base_case_id,
    implementation_status = "review",
    objective_gate_status = "pass",
    truth_distance_status = "pass",
    hit_rate_status = "pass",
    vb_mcmc_status = "pass",
    gate_status = "review",
    stringsAsFactors = FALSE
  ),
  file.path(ts_vb_conv_cal_dir, "replicated_assessment.csv"),
  row.names = FALSE
)

ts_vb_conv_dir <- tempfile("joint_qvp_ts_vb_conv_")
ts_vb_conv_result <- app_joint_qvp_run_ts_vb_convergence_audit(
  out_dir = ts_vb_conv_dir,
  calibration_dir = ts_vb_conv_cal_dir,
  max_iter_grid = c(5L),
  review_only = TRUE
)

ts_vb_conv_manifest <- utils::read.csv(
  file.path(ts_vb_conv_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
stopifnot(identical(
  ts_vb_conv_manifest$label,
  c("convergence_probe", "case_resolution_summary", "audit_summary", "audit_report")
))
stopifnot(all(nchar(ts_vb_conv_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_vb_conv_manifest))) {
  artifact_path <- file.path(ts_vb_conv_result$out_dir, ts_vb_conv_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_vb_conv_manifest$sha256[[ii]]))
}

ts_vb_conv_probe <- utils::read.csv(
  file.path(ts_vb_conv_result$out_dir, "convergence_probe.csv"),
  stringsAsFactors = FALSE
)
stopifnot(nrow(ts_vb_conv_probe) == 1L)
stopifnot(ts_vb_conv_probe$max_iter == 5L)
stopifnot(is.finite(ts_vb_conv_probe$qhat_truth_normalized_distance))

ts_vb_conv_summary <- utils::read.csv(
  file.path(ts_vb_conv_result$out_dir, "case_resolution_summary.csv"),
  stringsAsFactors = FALSE
)
stopifnot(nrow(ts_vb_conv_summary) == 1L)
stopifnot(ts_vb_conv_summary$resolution_status %in% c("resolved_by_iteration_grid", "still_max_iter"))
