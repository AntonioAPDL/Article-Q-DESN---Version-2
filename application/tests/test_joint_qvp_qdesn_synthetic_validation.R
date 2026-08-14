parallel_fixture <- app_joint_qvp_simulate_synthetic(
  Tn = 24L,
  p = 3L,
  tau = c(0.2, 0.5, 0.8),
  scenario = "parallel",
  seed = 1001L
)
stopifnot(identical(dim(parallel_fixture$Z), c(24L, 3L)))
stopifnot(identical(dim(parallel_fixture$true_q), c(24L, 3L)))
stopifnot(all(parallel_fixture$crossing_diagnostics$n_crossing_pairs == 0L))
stopifnot(length(parallel_fixture$y) == 24L)
stopifnot(all(is.finite(parallel_fixture$y)))

varying_fixture <- app_joint_qvp_simulate_synthetic(
  Tn = 20L,
  p = 2L,
  tau = c(0.25, 0.75),
  scenario = "slope_variation",
  seed = 1002L
)
stopifnot(identical(dim(varying_fixture$beta), c(2L, 2L)))
stopifnot(any(abs(varying_fixture$beta[, 1L] - varying_fixture$beta[, 2L]) > 0))

crossing_fixture <- app_joint_qvp_simulate_synthetic(
  Tn = 24L,
  p = 2L,
  tau = c(0.2, 0.5, 0.8),
  scenario = "crossing_pressure",
  seed = 1003L
)
stopifnot(any(crossing_fixture$crossing_diagnostics$n_crossing_pairs > 0L))

vb_fit <- app_joint_qvp_fit_al_vb_tiny(
  y = parallel_fixture$y,
  Z = parallel_fixture$Z[, 1:2, drop = FALSE],
  tau = c(0.25, 0.75),
  max_iter = 40L,
  tol = 1.0e-4,
  kappa = 0.5
)
stopifnot(inherits(vb_fit, "joint_qvp_qdesn_vb_fit"))
stopifnot(identical(vb_fit$manifest$inference[[1L]], "vb_tiny"))
stopifnot(all(is.finite(vb_fit$beta_mean)))
stopifnot(all(is.finite(vb_fit$sigma_mean)))
stopifnot(all(vb_fit$sigma_mean > 0))

fit <- app_joint_qvp_fit_al_mcmc_tiny(
  y = parallel_fixture$y,
  Z = parallel_fixture$Z[, 1:2, drop = FALSE],
  tau = c(0.25, 0.75),
  n_iter = 14L,
  burn = 7L,
  thin = 2L,
  seed = 1004L,
  kappa = 0.5,
  init = vb_fit,
  max_dense_dim = 20L
)
stopifnot(inherits(fit, "joint_qvp_qdesn_tiny_fit"))
stopifnot(identical(fit$manifest$likelihood[[1L]], "al"))
stopifnot(abs(fit$manifest$kappa[[1L]] - 0.5) < 1.0e-12)
stopifnot(identical(fit$init_source, "provided"))
