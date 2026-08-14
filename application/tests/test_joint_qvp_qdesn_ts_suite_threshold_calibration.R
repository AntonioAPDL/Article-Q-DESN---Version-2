ts_threshold_cal_dir <- tempfile("joint_qvp_ts_threshold_cal_")
ts_threshold_cal_scenarios <- app_joint_qvp_default_ts_synthetic_scenarios()[1, , drop = FALSE]
ts_threshold_cal_scenarios$Tn <- 24L
ts_threshold_cal_result <- app_joint_qvp_run_ts_suite_threshold_calibration(
  out_dir = ts_threshold_cal_dir,
  scenarios = ts_threshold_cal_scenarios,
  seeds = c(20260701L, 20260702L),
  vb_max_iter = 60L,
  adaptive_vb_max_iter_grid = 60L,
  n_chains = 2L,
  mcmc_n_iter = 40L,
  mcmc_burn = 20L,
  mcmc_thin = 5L,
  make_figures = FALSE
)

ts_threshold_cal_manifest <- utils::read.csv(
  file.path(ts_threshold_cal_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_ts_threshold_cal_labels <- c(
  "replicated_run_config",
  "replicated_assessment",
  "replicated_fit_summary",
  "replicated_vb_convergence_audit",
  "replicated_hit_rate_summary",
  "threshold_calibration_summary",
  "threshold_recommendations",
  "gate_frequency_summary",
  "provenance"
)
stopifnot(identical(ts_threshold_cal_manifest$label, expected_ts_threshold_cal_labels))
stopifnot(all(nchar(ts_threshold_cal_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_threshold_cal_manifest))) {
  artifact_path <- file.path(ts_threshold_cal_result$out_dir, ts_threshold_cal_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_threshold_cal_manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "replicated_run_config.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(run_config) == 2L)
stopifnot(length(unique(run_config$case_id)) == 2L)
stopifnot(all(run_config$base_case_id == ts_threshold_cal_scenarios$case_id[[1L]]))
stopifnot(identical(run_config$replicate_id, 1:2))
stopifnot(identical(run_config$seed, c(20260701L, 20260702L)))

fit_summary <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "replicated_fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_summary) == 2L)
stopifnot(identical(fit_summary$case_id, run_config$case_id))
stopifnot(all(fit_summary$base_case_id == ts_threshold_cal_scenarios$case_id[[1L]]))
stopifnot(all(fit_summary$Tn == 24L))
stopifnot(all(fit_summary$p == 5L))
stopifnot(all(fit_summary$K == 3L))
stopifnot(all(fit_summary$all_chains_warmstarted))
stopifnot(all(fit_summary$all_chain_draws_finite))
stopifnot(all(is.finite(fit_summary$vb_truth_normalized_qhat_distance)))
stopifnot(all(is.finite(fit_summary$pooled_mcmc_truth_normalized_qhat_distance)))
stopifnot(all(is.finite(fit_summary$vb_mcmc_max_normalized_distance)))
stopifnot(all(is.finite(fit_summary$objective_max_drop)))
stopifnot(all(fit_summary$vb_initial_max_iter == 60L))
stopifnot(all(fit_summary$vb_max_iter_grid == "60"))
stopifnot(all(fit_summary$vb_max_iter_used == 60L))
stopifnot(all(fit_summary$vb_retry_count == 0L))

vb_audit <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "replicated_vb_convergence_audit.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(vb_audit) == 2L)
stopifnot(identical(vb_audit$case_id, run_config$case_id))
stopifnot(all(vb_audit$base_case_id == ts_threshold_cal_scenarios$case_id[[1L]]))
stopifnot(all(vb_audit$attempt == 1L))
stopifnot(all(vb_audit$max_iter == 60L))
stopifnot(all(is.finite(vb_audit$final_max_beta_change)))

assessment <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "replicated_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(assessment) == 2L)
stopifnot(identical(assessment$case_id, fit_summary$case_id))
stopifnot(all(assessment$implementation_status %in% c("pass", "review", "fail")))
stopifnot(all(assessment$gate_status %in% c("pass", "review", "fail")))

hit_rate <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "replicated_hit_rate_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(hit_rate) == 2L * 3L * 3L)
stopifnot(identical(sort(unique(hit_rate$fit)), c("pooled_mcmc", "truth", "vb")))
stopifnot(all(is.finite(hit_rate$hit_rate_minus_tau)))

cal_summary <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "threshold_calibration_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(cal_summary) > 0L)
stopifnot(all(c("global_fit_summary", "scenario_fit_summary", "global_hit_rate", "scenario_hit_rate") %in% cal_summary$scope))
stopifnot(all(c("vb_truth_normalized_qhat_distance", "abs_hit_rate_error") %in% cal_summary$metric))
stopifnot(all(cal_summary$n_finite <= cal_summary$n))

recommendations <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "threshold_recommendations.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(recommendations) >= 8L)
stopifnot(all(c(
  "vb_truth_normalized_qhat_distance",
  "pooled_mcmc_truth_normalized_qhat_distance",
  "vb_mcmc_max_normalized_distance",
  "objective_max_drop",
  "overall_fail_fraction"
) %in% recommendations$metric))
stopifnot(all(is.finite(recommendations$candidate_review_threshold)))

gate_frequency <- utils::read.csv(file.path(ts_threshold_cal_result$out_dir, "gate_frequency_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(gate_frequency) > 0L)
stopifnot(all(c(ts_threshold_cal_scenarios$case_id[[1L]], "ALL") %in% gate_frequency$base_case_id))
stopifnot(all(gate_frequency$fraction >= 0 & gate_frequency$fraction <= 1))
