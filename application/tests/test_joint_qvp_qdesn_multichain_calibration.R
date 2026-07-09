wide_multichain_dir <- tempfile("joint_qvp_wide_multichain_")
wide_multichain_scenarios <- app_joint_qvp_default_wide_multichain_scenarios()
wide_multichain_scenarios$n_chains <- 2L
wide_multichain_scenarios$mcmc_n_iter <- 40L
wide_multichain_scenarios$mcmc_burn <- 20L
wide_multichain_scenarios$mcmc_thin <- 5L

wide_multichain_result <- app_joint_qvp_run_wide_multichain_mcmc_calibration(
  out_dir = wide_multichain_dir,
  scenarios = wide_multichain_scenarios
)

wide_multichain_manifest <- utils::read.csv(
  file.path(wide_multichain_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_multichain_labels <- c(
  "run_config",
  "multichain_thresholds",
  "multichain_assessment",
  "fit_summary",
  "chain_summary",
  "pooled_distance_summary",
  "mcmc_draw_summary",
  "crossing_summary",
  "rhs_prior_summary",
  "objective_diagnostics",
  "elbo_terms",
  "provenance"
)
stopifnot(identical(wide_multichain_manifest$label, expected_multichain_labels))
stopifnot(all(nchar(wide_multichain_manifest$sha256) == 64L))
for (ii in seq_len(nrow(wide_multichain_manifest))) {
  artifact_path <- file.path(wide_multichain_result$out_dir, wide_multichain_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), wide_multichain_manifest$sha256[[ii]]))
}

thresholds <- utils::read.csv(
  file.path(wide_multichain_result$out_dir, "multichain_thresholds.csv"),
  stringsAsFactors = FALSE
)
stopifnot(all(c(
  "artifact_reproducibility",
  "vb_converged",
  "warmstarted_mcmc_chains",
  "finite_chain_draws",
  "finite_pooled_distances",
  "finite_chain_to_pooled_distances",
  "fitted_crossing_pairs",
  "finite_mean_sigma_prior",
  "weak_proper_alpha_prior",
  "bounded_sigma_reference",
  "sigma_bound_hit_fraction",
  "chain_stability",
  "pooled_vb_mcmc_distance_pass",
  "pooled_vb_mcmc_distance_review"
) %in% thresholds$criterion))

fit_summary <- utils::read.csv(file.path(wide_multichain_result$out_dir, "fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_summary) == 1L)
stopifnot(identical(fit_summary$case_id[[1L]], "wide_tau_parallel_seed20260722_K3"))
stopifnot(fit_summary$n_chains[[1L]] == 2L)
stopifnot(fit_summary$mcmc_n_keep_per_chain[[1L]] == 4L)
stopifnot(fit_summary$mcmc_n_keep_total[[1L]] == 8L)
stopifnot(fit_summary$vb_status[[1L]] == "prototype_success")
stopifnot(isTRUE(fit_summary$vb_converged[[1L]]))
stopifnot(isTRUE(fit_summary$all_chains_warmstarted[[1L]]))
stopifnot(isTRUE(fit_summary$all_chain_draws_finite[[1L]]))
stopifnot(fit_summary$total_vb_crossing_pairs[[1L]] == 0L)
stopifnot(fit_summary$total_pooled_mcmc_crossing_pairs[[1L]] == 0L)
stopifnot(fit_summary$a_sigma[[1L]] == 2)
stopifnot(fit_summary$b_sigma[[1L]] == 1)
stopifnot(identical(fit_summary$alpha_prior_mean[[1L]], "empirical_quantile"))
stopifnot(identical(fit_summary$alpha_prior_mean_source[[1L]], "empirical_quantile"))
stopifnot(identical(fit_summary$alpha_prior_sd[[1L]], "1,1,1"))
stopifnot(fit_summary$max_sigma_upper_bound_hit_fraction[[1L]] == 0)
stopifnot(is.finite(fit_summary$pooled_max_normalized_distance[[1L]]))
stopifnot(is.finite(fit_summary$max_chain_to_pooled_normalized_distance[[1L]]))

assessment <- utils::read.csv(file.path(wide_multichain_result$out_dir, "multichain_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(assessment) == 1L)
stopifnot(assessment$implementation_status[[1L]] == "pass")
stopifnot(assessment$reference_status[[1L]] == "pass")
stopifnot(assessment$chain_stability_status[[1L]] == "pass")
stopifnot(assessment$distance_status[[1L]] == "pass")
stopifnot(assessment$gate_status[[1L]] == "pass")
stopifnot(assessment$crossing_pairs[[1L]] == 0L)

chain_summary <- utils::read.csv(file.path(wide_multichain_result$out_dir, "chain_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(chain_summary) == 2L)
stopifnot(identical(chain_summary$chain_id, 1:2))
stopifnot(all(is.finite(chain_summary$max_normalized_to_pooled)))

pooled_distance <- utils::read.csv(file.path(wide_multichain_result$out_dir, "pooled_distance_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(pooled_distance) == 1L)
stopifnot(is.finite(pooled_distance$max_normalized_distance[[1L]]))
stopifnot(pooled_distance$max_normalized_distance[[1L]] <= 5)

draw_summary <- utils::read.csv(file.path(wide_multichain_result$out_dir, "mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(draw_summary) == 2L * 3L)
stopifnot(identical(sort(unique(draw_summary$block)), c("alpha", "beta", "sigma")))
stopifnot(all(draw_summary$all_finite))
stopifnot(all(draw_summary$n_draws == 4L))
sigma_draw_summary <- draw_summary[draw_summary$block == "sigma", , drop = FALSE]
stopifnot(all(sigma_draw_summary$upper_bound_hit_fraction == 0))

repeat_dir <- tempfile("joint_qvp_wide_multichain_repeat_")
repeat_result <- app_joint_qvp_run_wide_multichain_mcmc_calibration(
  out_dir = repeat_dir,
  scenarios = wide_multichain_scenarios
)
repeat_manifest <- utils::read.csv(file.path(repeat_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(wide_multichain_manifest$label, repeat_manifest$label))
stopifnot(identical(wide_multichain_manifest$relative_path, repeat_manifest$relative_path))
stopifnot(identical(wide_multichain_manifest$sha256, repeat_manifest$sha256))
