artifact_dir <- tempfile("joint_qvp_synthetic_artifacts_")
artifact_result <- app_joint_qvp_run_synthetic_vb_validation(
  out_dir = artifact_dir,
  scenarios = data.frame(
    scenario = "parallel",
    seed = 20260712L,
    Tn = 12L,
    p = 2L,
    tau = "0.5",
    noise_sd = 0.05,
    stringsAsFactors = FALSE
  ),
  al_max_iter = 18L,
  exal_max_iter = 10L,
  mcmc_n_iter = 8L,
  mcmc_burn = 4L,
  mcmc_thin = 2L
)

manifest_path <- file.path(artifact_result$out_dir, "artifact_manifest.csv")
stopifnot(file.exists(manifest_path))
artifact_manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
expected_labels <- c(
  "run_config",
  "validation_thresholds",
  "validation_assessment",
  "fit_summary",
  "crossing_summary",
  "rhs_prior_summary",
  "monitor_terms",
  "elbo_terms",
  "objective_diagnostics",
  "warmstart_summary"
)
stopifnot(identical(artifact_manifest$label, expected_labels))
stopifnot(all(nchar(artifact_manifest$sha256) == 64L))
for (ii in seq_len(nrow(artifact_manifest))) {
  artifact_path <- file.path(artifact_result$out_dir, artifact_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), artifact_manifest$sha256[[ii]]))
}

fit_summary <- utils::read.csv(file.path(artifact_result$out_dir, "fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(identical(sort(fit_summary$method), c("al_vb", "exal_vb_ld")))
stopifnot(all(fit_summary$kappa == 1))
stopifnot(all(is.finite(fit_summary$rhs_mean_precision)))
stopifnot(all(fit_summary$rhs_mean_precision > 0))
stopifnot(all(fit_summary$K == 1L))
stopifnot("final_partial_elbo" %in% names(fit_summary))
stopifnot(is.finite(fit_summary$final_partial_elbo[fit_summary$method == "al_vb"]))
stopifnot(is.na(fit_summary$final_partial_elbo[fit_summary$method == "exal_vb_ld"]))
stopifnot(all(c("objective_status", "objective_max_drop", "objective_n_decreases") %in% names(fit_summary)))
stopifnot(fit_summary$objective_status[fit_summary$method == "al_vb"] == "pass")
stopifnot(is.finite(fit_summary$objective_max_drop[fit_summary$method == "al_vb"]))
stopifnot(fit_summary$objective_max_drop[fit_summary$method == "al_vb"] <= 1.0e-8)
stopifnot(all(is.finite(fit_summary$beta_l2_to_mcmc)))
stopifnot(all(is.finite(fit_summary$alpha_l2_to_mcmc)))
stopifnot(all(is.finite(fit_summary$sigma_l2_to_mcmc)))
stopifnot(is.na(fit_summary$gamma_l2_to_mcmc[fit_summary$method == "al_vb"]))
stopifnot(is.finite(fit_summary$gamma_l2_to_mcmc[fit_summary$method == "exal_vb_ld"]))

warmstart_summary <- utils::read.csv(file.path(artifact_result$out_dir, "warmstart_summary.csv"), stringsAsFactors = FALSE)
stopifnot(identical(sort(warmstart_summary$method), c("al_mcmc_from_vb", "exal_mcmc_from_vb_ld")))
stopifnot(all(warmstart_summary$init_source == "provided"))
stopifnot(all(warmstart_summary$all_finite))

monitor_terms <- utils::read.csv(file.path(artifact_result$out_dir, "monitor_terms.csv"), stringsAsFactors = FALSE)
stopifnot(all(c("likelihood_quadratic", "prior_quadratic", "beta_entropy_logdet") %in% unique(monitor_terms$term)))
stopifnot(all(is.finite(monitor_terms$value)))

elbo_terms <- utils::read.csv(file.path(artifact_result$out_dir, "elbo_terms.csv"), stringsAsFactors = FALSE)
stopifnot(identical(unique(elbo_terms$method), "al_vb"))
stopifnot(all(c(
  "expected_log_observation_quadratic_kernel",
  "expected_log_v_log_kernel",
  "expected_log_v_rate_kernel",
  "expected_log_sigma_power_kernel",
  "expected_log_beta_prior_kernel",
  "expected_log_beta_prior_log_precision_approx",
  "expected_log_sigma_prior_kernel",
  "expected_log_rhs_scale_prior_kernel",
  "q_beta_entropy",
  "q_sigma_entropy",
  "q_v_entropy",
  "q_rhs_scale_entropy"
) %in% unique(elbo_terms$term)))
included_elbo <- elbo_terms[elbo_terms$included_in_partial_elbo, , drop = FALSE]
excluded_elbo <- elbo_terms[!elbo_terms$included_in_partial_elbo, , drop = FALSE]
stopifnot(all(is.finite(included_elbo$value)))
stopifnot(all(is.na(excluded_elbo$value)))
stopifnot(all(c("expected_log_v_log_kernel", "q_v_entropy") %in% included_elbo$term))
stopifnot(all(c(
  "expected_log_rhs_scale_prior_kernel",
  "q_rhs_scale_entropy",
  "expected_log_beta_prior_log_precision_approx"
) %in% included_elbo$term))
stopifnot(any(included_elbo$status == "included_log_precision_mean_field_approximation"))
stopifnot(identical(unique(excluded_elbo$term), "alpha_point_mass_entropy"))

objective_diagnostics <- utils::read.csv(file.path(artifact_result$out_dir, "objective_diagnostics.csv"), stringsAsFactors = FALSE)
stopifnot(identical(sort(objective_diagnostics$method), c("al_vb", "exal_vb_ld")))
stopifnot(all(c(
  "objective_label",
  "max_drop",
  "n_decreases",
  "monotone_within_tolerance",
  "objective_status"
) %in% names(objective_diagnostics)))
stopifnot(objective_diagnostics$objective_status[objective_diagnostics$method == "al_vb"] == "pass")
stopifnot(objective_diagnostics$monotone_within_tolerance[objective_diagnostics$method == "al_vb"])
stopifnot(is.finite(objective_diagnostics$max_drop[objective_diagnostics$method == "al_vb"]))

thresholds <- utils::read.csv(file.path(artifact_result$out_dir, "validation_thresholds.csv"), stringsAsFactors = FALSE)
stopifnot(all(c(
  "artifact_reproducibility",
  "finite_vb_summaries",
  "finite_al_partial_elbo_terms",
  "al_objective_monotonicity_review",
  "warmstarted_mcmc_finite",
  "fitted_crossing_pairs",
  "vb_mcmc_normalized_distance_pass",
  "vb_mcmc_normalized_distance_review"
) %in% thresholds$criterion))

assessment <- utils::read.csv(file.path(artifact_result$out_dir, "validation_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(identical(sort(assessment$method), c("al_vb", "exal_vb_ld")))
stopifnot(all(assessment$implementation_status == "pass"))
stopifnot(!any(assessment$gate_status == "fail"))
stopifnot(all(assessment$distance_status %in% c("pass", "review")))
stopifnot(all(assessment$objective_status %in% c("pass", "review")))
stopifnot(all(is.finite(assessment$max_normalized_distance)))
stopifnot(all(assessment$warmstart_ok))

repeat_dir <- tempfile("joint_qvp_synthetic_artifacts_repeat_")
repeat_result <- app_joint_qvp_run_synthetic_vb_validation(
  out_dir = repeat_dir,
  scenarios = data.frame(
    scenario = "parallel",
    seed = 20260712L,
    Tn = 12L,
    p = 2L,
    tau = "0.5",
    noise_sd = 0.05,
    stringsAsFactors = FALSE
  ),
  al_max_iter = 18L,
  exal_max_iter = 10L,
  mcmc_n_iter = 8L,
  mcmc_burn = 4L,
  mcmc_thin = 2L
)
repeat_manifest <- utils::read.csv(file.path(repeat_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(artifact_manifest$label, repeat_manifest$label))
stopifnot(identical(artifact_manifest$relative_path, repeat_manifest$relative_path))
stopifnot(identical(artifact_manifest$sha256, repeat_manifest$sha256))
