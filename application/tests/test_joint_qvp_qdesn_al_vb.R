fixture <- app_joint_qvp_simulate_synthetic(
  Tn = 18L,
  p = 2L,
  tau = c(0.25, 0.75),
  scenario = "slope_variation",
  seed = 20260702,
  noise_sd = 0.05
)

vb <- app_joint_qvp_fit_al_vb_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 40L,
  tol = 1.0e-4,
  kappa = 0.5,
  tau0 = 1
)

stopifnot(inherits(vb, "joint_qvp_qdesn_vb_fit"))
stopifnot(length(vb$beta_mean) == 4L)
stopifnot(identical(dim(vb$beta_cov), c(4L, 4L)))
stopifnot(length(vb$alpha_mean) == 2L)
stopifnot(length(vb$sigma_mean) == 2L)
stopifnot(all(is.finite(vb$beta_mean)))
stopifnot(all(is.finite(vb$beta_cov)))
stopifnot(all(is.finite(vb$alpha_mean)))
stopifnot(all(is.finite(vb$sigma_mean)))
stopifnot(all(vb$sigma_mean > 0))
stopifnot(diff(vb$alpha_mean) >= -1.0e-12)
stopifnot(nrow(vb$trace) >= 1L)
stopifnot(all(is.finite(vb$trace$max_beta_change)))
stopifnot(all(c("rhs_mean_precision", "rhs_max_precision", "monitor") %in% names(vb$trace)))
stopifnot(all(is.finite(vb$trace$rhs_mean_precision)))
stopifnot(all(is.finite(vb$trace$rhs_max_precision)))
stopifnot(all(is.finite(vb$trace$monitor)))
stopifnot(is.data.frame(vb$rhs_prior_summary))
stopifnot(all(c("block", "mean_precision", "max_precision") %in% names(vb$rhs_prior_summary)))
stopifnot(all(is.finite(vb$rhs_prior_summary$mean_precision)))
stopifnot(all(vb$rhs_prior_summary$mean_precision > 0))
stopifnot(any(abs(vb$rhs_prior_summary$mean_precision - 1) > 1.0e-8))
stopifnot(is.data.frame(vb$monitor_terms))
stopifnot(all(c("likelihood_quadratic", "latent_linear", "prior_quadratic", "beta_entropy_logdet") %in% unique(vb$monitor_terms$term)))
stopifnot(all(is.finite(vb$monitor_terms$value)))
stopifnot(identical(vb$monitor_label, "al_vb_coordinate_monitor"))
stopifnot(is.data.frame(vb$elbo_terms))
stopifnot(identical(vb$elbo_label, "al_vb_rhs_accounted_elbo_missing_alpha_entropy_log_precision_approx"))
stopifnot(is.data.frame(vb$rhs_elbo_terms))
stopifnot(all(is.finite(vb$rhs_elbo_terms$value)))
stopifnot(is.data.frame(vb$objective_diagnostics))
stopifnot(identical(vb$objective_diagnostics$objective_status[[1L]], "pass"))
stopifnot(isTRUE(vb$objective_diagnostics$monotone_within_tolerance[[1L]]))
stopifnot(vb$objective_diagnostics$max_drop[[1L]] <= vb$objective_diagnostics$tolerance[[1L]])
stopifnot("partial_elbo" %in% names(vb$trace))
stopifnot(all(is.finite(vb$trace$partial_elbo)))
required_elbo_terms <- c(
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
)
stopifnot(all(required_elbo_terms %in% unique(vb$elbo_terms$term)))
included_elbo <- vb$elbo_terms[vb$elbo_terms$included_in_partial_elbo, , drop = FALSE]
excluded_elbo <- vb$elbo_terms[!vb$elbo_terms$included_in_partial_elbo, , drop = FALSE]
stopifnot(nrow(included_elbo) > 0L)
stopifnot(nrow(excluded_elbo) > 0L)
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
final_terms <- included_elbo[included_elbo$iter == max(vb$elbo_terms$iter), , drop = FALSE]
stopifnot(abs(sum(final_terms$value) - tail(vb$trace$partial_elbo, 1L)) < 1.0e-8)
stopifnot(identical(vb$manifest$likelihood[[1L]], "al"))
stopifnot(identical(vb$manifest$inference[[1L]], "vb_tiny"))
stopifnot(abs(vb$manifest$kappa[[1L]] - 0.5) < 1.0e-12)

vb_alpha_prior <- app_joint_qvp_fit_al_vb_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 40L,
  tol = 1.0e-4,
  kappa = 0.5,
  tau0 = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1
)
stopifnot(inherits(vb_alpha_prior, "joint_qvp_qdesn_vb_fit"))
stopifnot(identical(vb_alpha_prior$alpha_prior_mean_source, "empirical_quantile"))
stopifnot(all(vb_alpha_prior$alpha_prior_sd == 1))
stopifnot(all(is.finite(vb_alpha_prior$alpha_prior_mean)))
stopifnot(all(is.finite(vb_alpha_prior$alpha_mean)))

mcmc_from_vb <- app_joint_qvp_fit_al_mcmc_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  n_iter = 14L,
  burn = 7L,
  thin = 2L,
  seed = 20260703,
  kappa = 0.5,
  init = vb,
  max_dense_dim = 20L
)
stopifnot(inherits(mcmc_from_vb, "joint_qvp_qdesn_tiny_fit"))
stopifnot(identical(mcmc_from_vb$init_source, "provided"))
stopifnot(all(is.finite(mcmc_from_vb$beta_draws)))
stopifnot(all(mcmc_from_vb$sigma_draws > 0))

bad_vb <- try(app_joint_qvp_fit_al_vb_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 5L,
  kappa = -1
), silent = TRUE)
stopifnot(inherits(bad_vb, "try-error"))

bad_rhs_vb <- try(app_joint_qvp_fit_al_vb_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 5L,
  rhs_vb_inner = 0L
), silent = TRUE)
stopifnot(inherits(bad_rhs_vb, "try-error"))

bad_alpha_prior <- try(app_joint_qvp_fit_al_vb_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 5L,
  alpha_prior_sd = 0
), silent = TRUE)
stopifnot(inherits(bad_alpha_prior, "try-error"))
