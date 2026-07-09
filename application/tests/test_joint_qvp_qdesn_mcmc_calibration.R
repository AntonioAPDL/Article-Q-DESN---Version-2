calibration_dir <- tempfile("joint_qvp_mcmc_calibration_")
calibration_scenarios <- app_joint_qvp_default_objective_stress_scenarios()[5:6, ]
calibration_scenarios$mcmc_n_iter <- 30L
calibration_scenarios$mcmc_burn <- 15L
calibration_scenarios$mcmc_thin <- 3L

calibration_result <- app_joint_qvp_run_al_vb_mcmc_calibration(
  out_dir = calibration_dir,
  scenarios = calibration_scenarios
)

calibration_manifest <- utils::read.csv(
  file.path(calibration_result$out_dir, "artifact_manifest.csv"),
  stringsAsFactors = FALSE
)
expected_calibration_labels <- c(
  "run_config",
  "calibration_thresholds",
  "calibration_assessment",
  "fit_summary",
  "distance_summary",
  "mcmc_draw_summary",
  "crossing_summary",
  "rhs_prior_summary",
  "objective_diagnostics",
  "elbo_terms",
  "provenance"
)
stopifnot(identical(calibration_manifest$label, expected_calibration_labels))
stopifnot(all(nchar(calibration_manifest$sha256) == 64L))
for (ii in seq_len(nrow(calibration_manifest))) {
  artifact_path <- file.path(calibration_result$out_dir, calibration_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), calibration_manifest$sha256[[ii]]))
}

thresholds <- utils::read.csv(
  file.path(calibration_result$out_dir, "calibration_thresholds.csv"),
  stringsAsFactors = FALSE
)
stopifnot(all(c(
  "artifact_reproducibility",
  "vb_converged",
  "warmstarted_mcmc",
  "finite_mcmc_draws",
  "finite_vb_mcmc_distances",
  "fitted_crossing_pairs",
  "finite_mean_sigma_prior",
  "bounded_sigma_reference",
  "sigma_bound_hit_fraction",
  "vb_mcmc_normalized_distance_pass",
  "vb_mcmc_normalized_distance_review"
) %in% thresholds$criterion))

fit_summary <- utils::read.csv(file.path(calibration_result$out_dir, "fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_summary) == nrow(calibration_scenarios))
stopifnot(all(fit_summary$vb_status == "prototype_success"))
stopifnot(all(fit_summary$vb_converged))
stopifnot(all(fit_summary$mcmc_init_source == "provided"))
stopifnot(all(fit_summary$mcmc_n_keep == 5L))
stopifnot(all(fit_summary$mcmc_draws_all_finite))
stopifnot(all(fit_summary$total_vb_crossing_pairs == 0L))
stopifnot(all(fit_summary$total_mcmc_crossing_pairs == 0L))
stopifnot(all(is.finite(fit_summary$final_partial_elbo)))
stopifnot(all(fit_summary$objective_status == "pass"))
stopifnot(all(fit_summary$sigma_lower_bound == 1.0e-8))
stopifnot(all(fit_summary$sigma_upper_bound >= 1))
stopifnot(all(fit_summary$a_sigma == 2))
stopifnot(all(fit_summary$b_sigma == 1))
stopifnot(all(fit_summary$max_sigma_upper_bound_hit_fraction == 0))
stopifnot(all(is.finite(fit_summary$max_normalized_distance)))

distance_summary <- utils::read.csv(file.path(calibration_result$out_dir, "distance_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(distance_summary) == nrow(calibration_scenarios))
stopifnot(all(is.finite(distance_summary$max_normalized_distance)))
stopifnot(all(distance_summary$max_normalized_distance <= 5))

draw_summary <- utils::read.csv(file.path(calibration_result$out_dir, "mcmc_draw_summary.csv"), stringsAsFactors = FALSE)
stopifnot(identical(sort(unique(draw_summary$block)), c("alpha", "beta", "sigma")))
stopifnot(all(draw_summary$all_finite))
stopifnot(all(draw_summary$n_draws == 5L))
stopifnot(all(draw_summary$n_parameters > 0L))
stopifnot(all(is.finite(draw_summary$mean_draw_sd)))
stopifnot(all(c(
  "lower_bound",
  "upper_bound",
  "lower_bound_hit_fraction",
  "upper_bound_hit_fraction"
) %in% names(draw_summary)))
sigma_draw_summary <- draw_summary[draw_summary$block == "sigma", , drop = FALSE]
stopifnot(all(is.finite(sigma_draw_summary$lower_bound)))
stopifnot(all(is.finite(sigma_draw_summary$upper_bound)))
stopifnot(all(is.finite(sigma_draw_summary$lower_bound_hit_fraction)))
stopifnot(all(is.finite(sigma_draw_summary$upper_bound_hit_fraction)))

assessment <- utils::read.csv(file.path(calibration_result$out_dir, "calibration_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(assessment) == nrow(calibration_scenarios))
stopifnot(all(assessment$implementation_status == "pass"))
stopifnot(all(assessment$reference_status == "pass"))
stopifnot(all(assessment$distance_status == "pass"))
stopifnot(all(assessment$gate_status == "pass"))
stopifnot(all(assessment$warmstart_ok))
stopifnot(all(assessment$crossing_pairs == 0L))
stopifnot(all(assessment$max_sigma_upper_bound_hit_fraction == 0))

elbo_terms <- utils::read.csv(file.path(calibration_result$out_dir, "elbo_terms.csv"), stringsAsFactors = FALSE)
stopifnot(all(elbo_terms$iter %in% fit_summary$vb_max_iter | elbo_terms$iter < fit_summary$vb_max_iter))
stopifnot(all(is.finite(elbo_terms$value[elbo_terms$included_in_partial_elbo])))
stopifnot(identical(unique(elbo_terms$term[!elbo_terms$included_in_partial_elbo]), "alpha_point_mass_entropy"))

provenance <- utils::read.csv(file.path(calibration_result$out_dir, "provenance.csv"), stringsAsFactors = FALSE)
stopifnot(all(c("repo_root", "git_branch", "git_head", "git_status_sha256", "r_version", "rng_kind") %in% provenance$key))
stopifnot(all(nzchar(provenance$value)))

repeat_dir <- tempfile("joint_qvp_mcmc_calibration_repeat_")
repeat_result <- app_joint_qvp_run_al_vb_mcmc_calibration(
  out_dir = repeat_dir,
  scenarios = calibration_scenarios
)
repeat_manifest <- utils::read.csv(file.path(repeat_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(calibration_manifest$label, repeat_manifest$label))
stopifnot(identical(calibration_manifest$relative_path, repeat_manifest$relative_path))
stopifnot(identical(calibration_manifest$sha256, repeat_manifest$sha256))
