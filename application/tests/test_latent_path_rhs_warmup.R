rhs_test_args <- list(tau0 = 0.2, a_zeta = 2, b_zeta = 4, intercept_prec = 1.0e-9)
rhs_test_mean <- c(0.4, -0.2, 0.1)
rhs_test_cov <- diag(c(0.3, 0.2, 0.1))

rhs25 <- app_latent_rhs_state_init(
  p = 3L,
  intercept_index = 1L,
  args = rhs_test_args,
  rhs_control = list(freeze_tau_warmup_iters = 25L, update_every = 1L, min_tau_updates = 1L)
)
rhs25_tau_initial <- rhs25$e_inv_tau2
rhs25_xi_initial <- rhs25$e_inv_xi
rhs25_lambda_initial <- rhs25$e_inv_lambda2
for (iter in seq_len(25L)) {
  rhs25 <- app_latent_rhs_state_update(rhs25, rhs_test_mean, rhs_test_cov, iter = iter)
}
stopifnot(identical(rhs25$e_inv_tau2, rhs25_tau_initial))
stopifnot(identical(rhs25$e_inv_xi, rhs25_xi_initial))
stopifnot(!isTRUE(all.equal(rhs25$e_inv_lambda2, rhs25_lambda_initial)))
stopifnot(identical(rhs25$tau_update_count, 0L))
stopifnot(isTRUE(rhs25$last_warmup_active))

rhs25 <- app_latent_rhs_state_update(rhs25, rhs_test_mean, rhs_test_cov, iter = 26L)
stopifnot(!identical(rhs25$e_inv_tau2, rhs25_tau_initial))
stopifnot(!identical(rhs25$e_inv_xi, rhs25_xi_initial))
stopifnot(identical(rhs25$first_tau_update_iter, 26L))
stopifnot(identical(rhs25$tau_update_count, 1L))
stopifnot(!app_latent_prior_rhs_gate(rhs25, 26L)$passed)
rhs25 <- app_latent_rhs_state_update(rhs25, rhs_test_mean, rhs_test_cov, iter = 27L)
stopifnot(app_latent_prior_rhs_gate(rhs25, 27L)$passed)

rhs50 <- app_latent_rhs_state_init(
  p = 3L,
  intercept_index = 1L,
  args = rhs_test_args,
  rhs_control = list(freeze_tau_warmup_iters = 50L, update_every = 1L, min_tau_updates = 1L)
)
for (iter in seq_len(50L)) {
  rhs50 <- app_latent_rhs_state_update(rhs50, rhs_test_mean, rhs_test_cov, iter = iter)
}
stopifnot(identical(rhs50$e_inv_tau2, 1 / rhs_test_args$tau0^2))
rhs50 <- app_latent_rhs_state_update(rhs50, rhs_test_mean, rhs_test_cov, iter = 51L)
stopifnot(identical(rhs50$first_tau_update_iter, 51L))
stopifnot(!app_latent_prior_rhs_gate(rhs50, 51L)$passed)

rhs0 <- app_latent_rhs_state_init(
  p = 3L,
  intercept_index = 1L,
  args = rhs_test_args,
  rhs_control = list(freeze_tau_warmup_iters = 0L, update_every = 1L, min_tau_updates = 0L)
)
idx0 <- rhs0$penalized
e_theta2_0 <- rhs_test_mean^2 + diag(rhs_test_cov)
expected_lambda0 <- rhs0$e_inv_nu[idx0] + 0.5 * e_theta2_0[idx0] * rhs0$e_inv_tau2
expected_lambda0 <- 1 / expected_lambda0
expected_nu0 <- 1 / (1 + expected_lambda0)
expected_tau0 <- ((length(idx0) + 1) / 2) /
  (rhs0$e_inv_xi + 0.5 * sum(e_theta2_0[idx0] * expected_lambda0))
expected_xi0 <- 1 / (1 / rhs0$tau0^2 + expected_tau0)
rhs0 <- app_latent_rhs_state_update(rhs0, rhs_test_mean, rhs_test_cov, iter = 1L)
stopifnot(max(abs(rhs0$e_inv_lambda2[idx0] - expected_lambda0)) < 1.0e-14)
stopifnot(max(abs(rhs0$e_inv_nu[idx0] - expected_nu0)) < 1.0e-14)
stopifnot(abs(rhs0$e_inv_tau2 - expected_tau0) < 1.0e-14)
stopifnot(abs(rhs0$e_inv_xi - expected_xi0) < 1.0e-14)

rhs_cadence <- app_latent_normalize_rhs_control(list(
  freeze_tau_warmup_iters = 25L,
  update_every = 10L,
  min_tau_updates = 2L
))
stopifnot(identical(app_latent_rhs_minimum_convergence_iteration(rhs_cadence), 31L))

block_prior <- app_latent_prior_state_init(
  p = 6L,
  prior = "rhs_ns",
  intercept_index = c(1L, 4L),
  vb_args = list(
    beta_rhs = rhs_test_args,
    alpha_rhs = modifyList(rhs_test_args, list(tau0 = 0.05)),
    rhs = list(freeze_tau_warmup_iters = 25L, update_every = 1L, min_tau_updates = 1L)
  ),
  beta_index = 1:3,
  alpha_index = 4:6
)
for (iter in seq_len(26L)) {
  block_prior <- app_latent_prior_state_update(
    block_prior,
    theta_mean = c(rhs_test_mean, rhs_test_mean * 2),
    theta_cov = diag(rep(0.2, 6L)),
    iter = iter
  )
}
stopifnot(identical(block_prior$blocks$beta$state$first_tau_update_iter, 26L))
stopifnot(identical(block_prior$blocks$alpha$state$first_tau_update_iter, 26L))
stopifnot(block_prior$blocks$beta$state$e_inv_tau2 != block_prior$blocks$alpha$state$e_inv_tau2)
block_trace <- app_latent_prior_rhs_trace(block_prior, 26L)
stopifnot(identical(block_trace$block, c("beta", "alpha")))
stopifnot(all(block_trace$global_update_performed))
stopifnot(all(is.finite(block_trace$effective_tau)))

rhs_warmup_cfg <- list(
  inference = list(
    vb_ld = list(
      max_iter = 27L,
      max_iter_hard_cap = 100L,
      min_iter_elbo = 1L,
      tol = 1.0e6,
      n_draws = 4L,
      rhs_tau0 = 0.5,
      rhs_alpha_tau0 = 0.25,
      rhs_freeze_tau_warmup_iters = 25L,
      rhs_update_every = 1L,
      rhs_min_tau_updates = 1L,
      intercept_prec = 1.0e-9,
      sigma_a = 2,
      sigma_b = 1
    ),
    mcmc = list(rhs_tau0 = 0.5, rhs_alpha_tau0 = 0.25, intercept_prec = 1.0e-9),
    likelihood_family = "al"
  ),
  synthetic_recovery = list(
    n_history = 16L,
    horizon = 2L,
    n_members = 4L,
    seed = 20260809L,
    p0 = 0.5
  ),
  reservoir = list(seed = 20260809L)
)
rhs_warmup_sim <- app_latent_path_recovery_simulate(rhs_warmup_cfg)
rhs_warmup_design <- app_make_latent_path_recovery_design(rhs_warmup_sim, rhs_warmup_cfg)
rhs_warmup_args <- app_make_qdesn_discrepancy_vb_args(
  rhs_warmup_cfg,
  prior = "rhs_ns",
  seed = rhs_warmup_sim$seed,
  likelihood_family = "al"
)
rhs_warmup_fit <- app_fit_latent_path_al_vb_core(
  design = rhs_warmup_design,
  p0 = rhs_warmup_sim$p0,
  coefficient_prior = "rhs_ns",
  vb_args = rhs_warmup_args,
  seed = rhs_warmup_sim$seed
)
stopifnot(identical(rhs_warmup_fit$vb_diagnostics$iterations, 27L))
stopifnot(isTRUE(rhs_warmup_fit$vb_diagnostics$converged))
stopifnot(isTRUE(rhs_warmup_fit$vb_diagnostics$rhs_global_scale$convergence_gate_passed))
stopifnot(all(rhs_warmup_fit$vb_diagnostics$rhs_global_scale$blocks$first_tau_update_iter == 26L))
stopifnot(nrow(rhs_warmup_fit$vb_diagnostics$rhs_global_scale_trace) == 54L)
stopifnot(all(!rhs_warmup_fit$vb_diagnostics$rhs_global_scale_trace$global_update_performed[
  rhs_warmup_fit$vb_diagnostics$rhs_global_scale_trace$iteration <= 25L
]))

rhs_short_args <- rhs_warmup_args
rhs_short_args$max_iter <- 26L
rhs_short_error <- tryCatch({
  app_fit_latent_path_al_vb_core(
    design = rhs_warmup_design,
    p0 = rhs_warmup_sim$p0,
    coefficient_prior = "rhs_ns",
    vb_args = rhs_short_args,
    seed = rhs_warmup_sim$seed
  )
  FALSE
}, error = function(e) grepl("cannot satisfy the RHS global-scale schedule", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(rhs_short_error))

cat("Latent-path RHS global-scale warmup tests passed.\n")
