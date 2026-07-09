fixture <- app_joint_qvp_simulate_synthetic(
  Tn = 16L,
  p = 2L,
  tau = c(0.25, 0.75),
  scenario = "slope_variation",
  seed = 20260704,
  noise_sd = 0.05
)

fit <- app_joint_qvp_fit_exal_vb_ld_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 18L,
  tol = 1.0e-4,
  kappa = 0.5,
  tau0 = 1
)

support <- app_joint_qvp_exal_support(fixture$tau)
stopifnot(inherits(fit, "joint_qvp_qdesn_vb_fit"))
stopifnot(length(fit$beta_mean) == 4L)
stopifnot(identical(dim(fit$beta_cov), c(4L, 4L)))
stopifnot(length(fit$alpha_mean) == 2L)
stopifnot(length(fit$sigma_mean) == 2L)
stopifnot(length(fit$gamma_mean) == 2L)
stopifnot(identical(dim(fit$s_mean), c(16L, 2L)))
stopifnot(identical(dim(fit$v_mean), c(16L, 2L)))
stopifnot(all(is.finite(fit$beta_mean)))
stopifnot(all(is.finite(fit$beta_cov)))
stopifnot(all(is.finite(fit$alpha_mean)))
stopifnot(all(is.finite(fit$sigma_mean)))
stopifnot(all(is.finite(fit$gamma_mean)))
stopifnot(all(fit$sigma_mean > 0))
stopifnot(all(fit$s_mean >= 0))
stopifnot(all(fit$v_mean > 0))
stopifnot(diff(fit$alpha_mean) >= -1.0e-12)
stopifnot(all(fit$gamma_mean > support$lower))
stopifnot(all(fit$gamma_mean < support$upper))
stopifnot(nrow(fit$trace) >= 1L)
stopifnot(all(is.finite(fit$trace$max_beta_change)))
stopifnot(all(c("rhs_mean_precision", "rhs_max_precision", "monitor") %in% names(fit$trace)))
stopifnot(all(is.finite(fit$trace$rhs_mean_precision)))
stopifnot(all(is.finite(fit$trace$rhs_max_precision)))
stopifnot(all(is.finite(fit$trace$monitor)))
stopifnot(is.data.frame(fit$rhs_prior_summary))
stopifnot(all(c("block", "mean_precision", "max_precision") %in% names(fit$rhs_prior_summary)))
stopifnot(all(is.finite(fit$rhs_prior_summary$mean_precision)))
stopifnot(all(fit$rhs_prior_summary$mean_precision > 0))
stopifnot(any(abs(fit$rhs_prior_summary$mean_precision - 1) > 1.0e-8))
stopifnot(is.data.frame(fit$monitor_terms))
stopifnot(all(c(
  "likelihood_quadratic",
  "latent_linear",
  "positive_shift_quadratic",
  "prior_quadratic",
  "beta_entropy_logdet"
) %in% unique(fit$monitor_terms$term)))
stopifnot(all(is.finite(fit$monitor_terms$value)))
stopifnot(identical(fit$monitor_label, "approximate_vb_ld_coordinate_monitor"))
stopifnot(identical(fit$manifest$likelihood[[1L]], "exal"))
stopifnot(identical(fit$manifest$inference[[1L]], "vb_ld_tiny"))
stopifnot(abs(fit$manifest$kappa[[1L]] - 0.5) < 1.0e-12)

mcmc_from_vb <- app_joint_qvp_fit_exal_mcmc_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  n_iter = 12L,
  burn = 6L,
  thin = 2L,
  seed = 20260705,
  kappa = 0.5,
  init = fit,
  max_dense_dim = 20L
)
stopifnot(inherits(mcmc_from_vb, "joint_qvp_qdesn_tiny_fit"))
stopifnot(identical(mcmc_from_vb$init_source, "provided"))
stopifnot(all(is.finite(mcmc_from_vb$beta_draws)))
stopifnot(all(is.finite(mcmc_from_vb$gamma_draws)))
stopifnot(all(mcmc_from_vb$sigma_draws > 0))

bad_fit <- try(app_joint_qvp_fit_exal_vb_ld_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 5L,
  gamma_init = c(support$lower[[1L]], 0)
), silent = TRUE)
stopifnot(inherits(bad_fit, "try-error"))

bad_rhs_fit <- try(app_joint_qvp_fit_exal_vb_ld_tiny(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  max_iter = 5L,
  rhs_vb_inner = 0L
), silent = TRUE)
stopifnot(inherits(bad_rhs_fit, "try-error"))
