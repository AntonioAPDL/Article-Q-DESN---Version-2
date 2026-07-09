stress_dir <- tempfile("joint_qvp_objective_stress_")
stress_scenarios <- data.frame(
  stress_case = c("smoke_k1", "smoke_slope"),
  scenario = c("parallel", "slope_variation"),
  seed = c(20260731L, 20260732L),
  Tn = c(12L, 14L),
  p = c(2L, 2L),
  tau = c("0.5", "0.25,0.75"),
  noise_sd = c(0.05, 0.1),
  kappa = c(0.5, 0.75),
  tau0 = c(1, 0.5),
  max_iter = c(18L, 18L),
  rhs_vb_inner = c(3L, 3L),
  stringsAsFactors = FALSE
)

stress_result <- app_joint_qvp_run_al_vb_objective_stress(
  out_dir = stress_dir,
  scenarios = stress_scenarios
)

stress_manifest <- utils::read.csv(file.path(stress_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
expected_stress_labels <- c(
  "run_config",
  "stress_thresholds",
  "stress_assessment",
  "fit_summary",
  "objective_diagnostics",
  "crossing_summary",
  "rhs_prior_summary",
  "elbo_terms"
)
stopifnot(identical(stress_manifest$label, expected_stress_labels))
stopifnot(all(nchar(stress_manifest$sha256) == 64L))
for (ii in seq_len(nrow(stress_manifest))) {
  artifact_path <- file.path(stress_result$out_dir, stress_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), stress_manifest$sha256[[ii]]))
}

fit_summary <- utils::read.csv(file.path(stress_result$out_dir, "fit_summary.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(fit_summary) == nrow(stress_scenarios))
stopifnot(all(fit_summary$objective_status == "pass"))
stopifnot(all(is.finite(fit_summary$objective_max_drop)))
stopifnot(all(fit_summary$objective_max_drop <= 1.0e-8))
stopifnot(all(fit_summary$total_crossing_pairs == 0L))
stopifnot(all(is.finite(fit_summary$final_partial_elbo)))
stopifnot(all(is.finite(fit_summary$rhs_mean_precision)))
stopifnot(all(fit_summary$rhs_mean_precision > 0))

objective_diagnostics <- utils::read.csv(file.path(stress_result$out_dir, "objective_diagnostics.csv"), stringsAsFactors = FALSE)
stopifnot(all(objective_diagnostics$objective_status == "pass"))
stopifnot(all(objective_diagnostics$monotone_within_tolerance))

stress_assessment <- utils::read.csv(file.path(stress_result$out_dir, "stress_assessment.csv"), stringsAsFactors = FALSE)
stopifnot(all(stress_assessment$implementation_status == "pass"))
stopifnot(!any(stress_assessment$gate_status == "fail"))
stopifnot(all(stress_assessment$objective_status == "pass"))

elbo_terms <- utils::read.csv(file.path(stress_result$out_dir, "elbo_terms.csv"), stringsAsFactors = FALSE)
included_elbo <- elbo_terms[elbo_terms$included_in_partial_elbo, , drop = FALSE]
excluded_elbo <- elbo_terms[!elbo_terms$included_in_partial_elbo, , drop = FALSE]
stopifnot(all(is.finite(included_elbo$value)))
stopifnot(identical(unique(excluded_elbo$term), "alpha_point_mass_entropy"))

repeat_dir <- tempfile("joint_qvp_objective_stress_repeat_")
repeat_result <- app_joint_qvp_run_al_vb_objective_stress(
  out_dir = repeat_dir,
  scenarios = stress_scenarios
)
repeat_manifest <- utils::read.csv(file.path(repeat_result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(stress_manifest$label, repeat_manifest$label))
stopifnot(identical(stress_manifest$relative_path, repeat_manifest$relative_path))
stopifnot(identical(stress_manifest$sha256, repeat_manifest$sha256))
