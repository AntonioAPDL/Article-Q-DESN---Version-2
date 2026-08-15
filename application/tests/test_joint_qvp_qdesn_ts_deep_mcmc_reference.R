ts_deep_ref_cal_dir <- tempfile("joint_qvp_ts_deep_ref_cal_")
ts_deep_ref_scenarios <- app_joint_qvp_default_ts_synthetic_scenarios()[1, , drop = FALSE]
ts_deep_ref_scenarios$Tn <- 24L
ts_deep_ref_cal <- app_joint_qvp_run_ts_suite_threshold_calibration(
  out_dir = ts_deep_ref_cal_dir,
  scenarios = ts_deep_ref_scenarios,
  seeds = c(20260701L, 20260702L),
  vb_max_iter = 60L,
  adaptive_vb_max_iter_grid = 60L,
  n_chains = 2L,
  mcmc_n_iter = 40L,
  mcmc_burn = 20L,
  mcmc_thin = 5L,
  make_figures = FALSE
)

ts_deep_ref_dir <- tempfile("joint_qvp_ts_deep_ref_")
ts_deep_ref_result <- app_joint_qvp_run_ts_deep_mcmc_reference(
  out_dir = ts_deep_ref_dir,
  calibration_dir = ts_deep_ref_cal$out_dir,
  max_truth_targets = 1L,
  max_hit_targets = 1L,
  max_vb_mcmc_targets = 0L,
  max_objective_targets = 0L,
  vb_max_iter = 80L,
  adaptive_vb_max_iter_grid = 80L,
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  make_figures = TRUE,
  figure_case_limit = 1L,
  verbose = FALSE
)

ts_deep_ref_manifest <- utils::read.csv(
  file.path(ts_deep_ref_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
required_ts_deep_ref_labels <- c(
  "target_selection",
  "deep_reference_run_config",
  "deep_reference_assessment",
  "deep_reference_comparison",
  "deep_reference_resolution_summary",
  "deep_reference_fit_summary",
  "deep_reference_hit_rate_summary",
  "deep_reference_vb_mcmc_distance_summary",
  "deep_reference_chain_summary",
  "deep_reference_mcmc_draw_summary",
  "deep_reference_crossing_summary",
  "deep_reference_vb_convergence_audit",
  "objective_diagnostics",
  "elbo_terms",
  "figure_manifest",
  "provenance"
)
stopifnot(all(required_ts_deep_ref_labels %in% ts_deep_ref_manifest$label))
stopifnot(all(nchar(ts_deep_ref_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_deep_ref_manifest))) {
  artifact_path <- file.path(ts_deep_ref_result$out_dir, ts_deep_ref_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_deep_ref_manifest$sha256[[ii]]))
}

targets <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "target_selection.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(targets) >= 1L)
stopifnot(length(unique(targets$case_id)) == nrow(targets))
stopifnot(all(nzchar(targets$target_reason)))

run_config <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_run_config.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(run_config) == nrow(targets))
stopifnot(identical(run_config$case_id, targets$case_id))
stopifnot(all(run_config$n_chains == 2L))
stopifnot(all(run_config$mcmc_n_iter == 80L))

fit_summary <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_summary) == nrow(targets))
stopifnot(identical(fit_summary$case_id, targets$case_id))
stopifnot(all(fit_summary$all_chains_warmstarted))
stopifnot(all(fit_summary$all_chain_draws_finite))
stopifnot(all(is.finite(fit_summary$pooled_mcmc_truth_normalized_qhat_distance)))
stopifnot(all(is.finite(fit_summary$vb_mcmc_max_normalized_distance)))
stopifnot(all(is.finite(fit_summary$max_chain_to_pooled_normalized_distance)))
stopifnot(all(fit_summary$vb_initial_max_iter == 80L))
stopifnot(all(fit_summary$vb_max_iter_grid == "80"))
stopifnot(all(fit_summary$vb_max_iter_used == 80L))
stopifnot(all(fit_summary$vb_retry_count == 0L))

vb_audit <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_vb_convergence_audit.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(vb_audit) == nrow(targets))
stopifnot(identical(vb_audit$case_id, targets$case_id))
stopifnot(all(vb_audit$attempt == 1L))
stopifnot(all(vb_audit$max_iter == 80L))
stopifnot(all(is.finite(vb_audit$final_max_beta_change)))

assessment <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(assessment) == nrow(targets))
stopifnot(identical(assessment$case_id, targets$case_id))
stopifnot(all(assessment$implementation_status %in% c("pass", "review", "fail")))
stopifnot(all(assessment$gate_status %in% c("pass", "review", "fail")))

comparison <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_comparison.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(comparison) == nrow(targets))
stopifnot(identical(comparison$case_id, targets$case_id))
stopifnot(all(is.finite(comparison$delta_pooled_mcmc_truth_normalized_qhat_distance)))
stopifnot(all(is.finite(comparison$delta_vb_mcmc_max_normalized_distance)))
stopifnot(all(nzchar(comparison$deepening_interpretation)))

resolution <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_resolution_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(resolution) > 0L)
stopifnot(abs(sum(resolution$fraction) - 1) < 1.0e-12)

chains <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_chain_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(chains) == nrow(targets) * 2L)
stopifnot(all(is.finite(chains$max_normalized_to_pooled)))

draws <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "deep_reference_mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(draws) == nrow(targets) * 2L * 3L)
stopifnot(all(draws$all_finite))

figures <- utils::read.csv(file.path(ts_deep_ref_result$out_dir, "figure_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(figures) == 2L)
stopifnot(all(figures$size_bytes > 0))
stopifnot(all(nchar(figures$sha256) == 64L))
