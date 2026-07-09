alpha_gap_dir <- tempfile("joint_qvp_alpha_gap_audit_")
alpha_gap_scenarios <- app_joint_qvp_default_wide_multichain_scenarios()
alpha_gap_scenarios$n_chains <- 2L
alpha_gap_scenarios$mcmc_n_iter <- 40L
alpha_gap_scenarios$mcmc_burn <- 20L
alpha_gap_scenarios$mcmc_thin <- 5L

alpha_gap_result <- app_joint_qvp_run_wide_alpha_gap_audit(
  out_dir = alpha_gap_dir,
  scenarios = alpha_gap_scenarios,
  alpha_prior_sds = c(Inf, 1)
)

alpha_gap_manifest <- utils::read.csv(
  file.path(alpha_gap_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_alpha_gap_labels <- c(
  "run_config",
  "audit_assessment",
  "fit_distance_summary",
  "chain_stability_summary",
  "alpha_gap_summary",
  "quantile_fit_summary",
  "provenance"
)
stopifnot(identical(alpha_gap_manifest$label, expected_alpha_gap_labels))
stopifnot(all(nchar(alpha_gap_manifest$sha256) == 64L))
for (ii in seq_len(nrow(alpha_gap_manifest))) {
  artifact_path <- file.path(alpha_gap_result$out_dir, alpha_gap_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), alpha_gap_manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(alpha_gap_result$out_dir, "run_config.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(run_config) == 2L)
stopifnot(identical(run_config$alpha_prior_mean, c("none", "empirical_quantile")))
stopifnot(identical(run_config$n_chains, c(2L, 2L)))

alpha_gap_summary <- utils::read.csv(file.path(alpha_gap_result$out_dir, "alpha_gap_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(alpha_gap_summary) == 6L)
stopifnot(all(c(
  "al_A",
  "al_B",
  "resolved_alpha_prior_mean",
  "pooled_minus_vb_alpha",
  "pooled_alpha_q05",
  "pooled_alpha_q50",
  "pooled_alpha_q95"
) %in% names(alpha_gap_summary)))
stopifnot(all(is.finite(alpha_gap_summary$pooled_minus_vb_alpha)))
stopifnot(all(is.finite(alpha_gap_summary$pooled_alpha_q50)))

distance_summary <- utils::read.csv(file.path(alpha_gap_result$out_dir, "fit_distance_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(distance_summary) == 2L)
stopifnot(all(is.finite(distance_summary$max_normalized_distance)))
stopifnot(all(is.finite(distance_summary$alpha_normalized_distance)))
no_prior_alpha <- distance_summary$alpha_normalized_distance[grepl("alpha_sd_inf$", distance_summary$case_id)]
finite_prior_alpha <- distance_summary$alpha_normalized_distance[grepl("alpha_sd_1$", distance_summary$case_id)]
stopifnot(length(no_prior_alpha) == 1L)
stopifnot(length(finite_prior_alpha) == 1L)
stopifnot(finite_prior_alpha < no_prior_alpha)

assessment <- utils::read.csv(file.path(alpha_gap_result$out_dir, "audit_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(assessment) == 2L)
stopifnot(all(assessment$gate_status %in% c("pass", "review")))
stopifnot(all(assessment$issue_class %in% c(
  "alpha_drift_not_chain_noise",
  "alpha_gap_stabilized",
  "mixed_gap",
  "no_prior_short_reference_stable"
)))

quantile_fit_summary <- utils::read.csv(file.path(alpha_gap_result$out_dir, "quantile_fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(quantile_fit_summary) == 12L)
stopifnot(identical(sort(unique(quantile_fit_summary$fit)), c("pooled_mcmc", "vb")))
stopifnot(all(is.finite(quantile_fit_summary$empirical_hit_rate)))
stopifnot(all(quantile_fit_summary$empirical_hit_rate >= 0 & quantile_fit_summary$empirical_hit_rate <= 1))
