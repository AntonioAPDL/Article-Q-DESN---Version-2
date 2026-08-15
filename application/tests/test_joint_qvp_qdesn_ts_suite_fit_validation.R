ts_suite_fit_dir <- tempfile("joint_qvp_ts_suite_fit_")
ts_suite_fit_scenarios <- app_joint_qvp_default_ts_synthetic_scenarios()[1:2, ]
ts_suite_fit_scenarios$Tn <- 24L
ts_suite_fit_result <- app_joint_qvp_run_ts_suite_fit_validation(
  out_dir = ts_suite_fit_dir,
  scenarios = ts_suite_fit_scenarios,
  vb_max_iter = 80L,
  adaptive_vb_max_iter_grid = 80L,
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  make_figures = TRUE
)

ts_suite_fit_manifest <- utils::read.csv(
  file.path(ts_suite_fit_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_ts_suite_fit_figure_labels <- unlist(lapply(ts_suite_fit_scenarios$case_id, function(case_id) {
  c(paste0(case_id, "_fit_overlay"), paste0(case_id, "_error_hit"))
}), use.names = FALSE)
expected_ts_suite_fit_labels <- c(
  "run_config",
  "suite_assessment",
  "suite_fit_summary",
  "truth_fit_summary",
  "readout_truth_summary",
  "vb_mcmc_distance_summary",
  "chain_summary",
  "mcmc_draw_summary",
  "crossing_summary",
  "vb_convergence_audit",
  "objective_diagnostics",
  "elbo_terms",
  "figure_manifest",
  "provenance",
  expected_ts_suite_fit_figure_labels
)
stopifnot(identical(ts_suite_fit_manifest$label, expected_ts_suite_fit_labels))
stopifnot(all(nchar(ts_suite_fit_manifest$sha256) == 64L))
for (ii in seq_len(nrow(ts_suite_fit_manifest))) {
  artifact_path <- file.path(ts_suite_fit_result$out_dir, ts_suite_fit_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), ts_suite_fit_manifest$sha256[[ii]]))
}

suite_fit <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "suite_fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(suite_fit) == 2L)
stopifnot(identical(suite_fit$case_id, ts_suite_fit_scenarios$case_id))
stopifnot(all(suite_fit$Tn == 24L))
stopifnot(all(suite_fit$p == 5L))
stopifnot(all(suite_fit$K == 3L))
stopifnot(all(suite_fit$vb_status %in% c("prototype_success", "prototype_max_iter")))
stopifnot(all(suite_fit$all_chains_warmstarted))
stopifnot(all(suite_fit$all_chain_draws_finite))
stopifnot(all(suite_fit$total_vb_crossing_pairs == 0L))
stopifnot(all(suite_fit$total_pooled_mcmc_crossing_pairs == 0L))
stopifnot(all(suite_fit$max_sigma_upper_bound_hit_fraction == 0))
stopifnot(all(is.finite(suite_fit$vb_truth_normalized_qhat_distance)))
stopifnot(all(is.finite(suite_fit$pooled_mcmc_truth_normalized_qhat_distance)))
stopifnot(all(is.finite(suite_fit$vb_mcmc_max_normalized_distance)))
stopifnot(all(is.finite(suite_fit$max_chain_to_pooled_normalized_distance)))
stopifnot(all(c(
  "vb_initial_max_iter",
  "vb_max_iter_grid",
  "vb_max_iter_used",
  "vb_retry_count",
  "vb_convergence_policy",
  "vb_final_max_beta_change"
) %in% names(suite_fit)))
stopifnot(all(suite_fit$vb_initial_max_iter == 80L))
stopifnot(all(suite_fit$vb_max_iter_grid == "80"))
stopifnot(all(suite_fit$vb_max_iter_used == 80L))
stopifnot(all(suite_fit$vb_retry_count == 0L))
stopifnot(all(suite_fit$vb_convergence_policy == "fixed_max_iter"))
stopifnot(all(is.finite(suite_fit$vb_final_max_beta_change)))

vb_audit <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "vb_convergence_audit.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(vb_audit) == 2L)
stopifnot(identical(vb_audit$case_id, ts_suite_fit_scenarios$case_id))
stopifnot(all(vb_audit$attempt == 1L))
stopifnot(all(vb_audit$max_iter == 80L))
stopifnot(all(vb_audit$status %in% c("prototype_success", "prototype_max_iter")))
stopifnot(all(is.finite(vb_audit$final_max_beta_change)))

assessment <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "suite_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(assessment) == 2L)
stopifnot(identical(assessment$case_id, suite_fit$case_id))
stopifnot(all(assessment$implementation_status %in% c("pass", "review")))
stopifnot(all(assessment$objective_gate_status %in% c("pass", "review")))
stopifnot(all(assessment$truth_distance_status %in% c("pass", "review")))
stopifnot(all(assessment$hit_rate_status %in% c("pass", "review")))
stopifnot(all(assessment$vb_mcmc_status %in% c("pass", "review")))
stopifnot(all(assessment$gate_status %in% c("pass", "review")))
stopifnot(all(is.finite(assessment$max_hit_rate_error)))
stopifnot(all(is.finite(assessment$max_hit_rate_allowed)))

truth_fit <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "truth_fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(truth_fit) == 2L * 3L * 3L)
stopifnot(identical(sort(unique(truth_fit$fit)), c("pooled_mcmc", "truth", "vb")))
truth_rows <- truth_fit[truth_fit$fit == "truth", , drop = FALSE]
stopifnot(max(abs(truth_rows$rmse_to_truth)) < 1.0e-12)
stopifnot(all(is.finite(truth_fit$empirical_hit_rate)))
stopifnot(all(truth_fit$empirical_hit_rate >= 0 & truth_fit$empirical_hit_rate <= 1))

readout <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "readout_truth_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(readout) == 2L * 2L * 3L * (1L + 5L))
stopifnot(all(is.finite(readout$error)))

distance <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "vb_mcmc_distance_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(distance) == 2L)
stopifnot(all(is.finite(distance$max_normalized_distance)))

chains <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "chain_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(chains) == 2L * 2L)
stopifnot(all(is.finite(chains$max_normalized_to_pooled)))

draws <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(draws) == 2L * 2L * 3L)
stopifnot(all(draws$all_finite))

crossing <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "crossing_summary.csv"), stringsAsFactors = FALSE)
stopifnot(sum(crossing$n_crossing_pairs) == 0L)

figures <- utils::read.csv(file.path(ts_suite_fit_result$out_dir, "figure_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(figures) == 2L * 2L)
stopifnot(identical(figures$label, expected_ts_suite_fit_figure_labels))
stopifnot(all(figures$size_bytes > 0))
stopifnot(all(nchar(figures$sha256) == 64L))
