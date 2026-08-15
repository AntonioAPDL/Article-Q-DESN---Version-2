set.seed(20260701)
Tn <- 18L
Z <- cbind(
  x1 = seq(-1, 1, length.out = Tn),
  x2 = sin(seq(0, pi, length.out = Tn))
)
true_alpha <- c(-0.5, 0.25)
true_beta <- matrix(c(0.6, -0.2, 0.7, -0.1), nrow = 2L, ncol = 2L)
y <- as.numeric(true_alpha[[1L]] + Z %*% true_beta[, 1L] + stats::rnorm(Tn, sd = 0.15))
tau <- c(0.25, 0.75)

fit_a <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 24L,
  burn = 12L,
  thin = 2L,
  seed = 99L,
  kappa = 1,
  tau0 = 1,
  max_dense_dim = 20L
)
fit_b <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 24L,
  burn = 12L,
  thin = 2L,
  seed = 99L,
  kappa = 1,
  tau0 = 1,
  max_dense_dim = 20L
)

stopifnot(inherits(fit_a, "joint_qvp_qdesn_tiny_fit"))
stopifnot(identical(dim(fit_a$beta_draws), c(6L, 4L)))
stopifnot(identical(dim(fit_a$alpha_draws), c(6L, 2L)))
stopifnot(identical(dim(fit_a$sigma_draws), c(6L, 2L)))
stopifnot(all(is.finite(fit_a$beta_draws)))
stopifnot(all(is.finite(fit_a$alpha_draws)))
stopifnot(all(is.finite(fit_a$sigma_draws)))
stopifnot(all(fit_a$sigma_draws > 0))
stopifnot(all(apply(fit_a$alpha_draws, 1L, function(x) diff(x) >= -1.0e-12)))
stopifnot(identical(round(fit_a$beta_draws, 12), round(fit_b$beta_draws, 12)))
stopifnot(identical(round(fit_a$alpha_draws, 12), round(fit_b$alpha_draws, 12)))
stopifnot(identical(round(fit_a$sigma_draws, 12), round(fit_b$sigma_draws, 12)))
stopifnot(nrow(fit_a$crossing_diagnostics) == Tn)
stopifnot(identical(fit_a$manifest$status[[1L]], "prototype_success"))
stopifnot(identical(fit_a$manifest$likelihood[[1L]], "al"))
stopifnot(identical(fit_a$manifest$inference[[1L]], "mcmc_tiny"))

kappa_half <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 18L,
  burn = 9L,
  thin = 3L,
  seed = 101L,
  kappa = 0.5
)
stopifnot(inherits(kappa_half, "joint_qvp_qdesn_tiny_fit"))
stopifnot(abs(kappa_half$manifest$kappa[[1L]] - 0.5) < 1.0e-12)
stopifnot(all(is.finite(kappa_half$beta_draws)))
stopifnot(all(kappa_half$sigma_draws > 0))

alpha_prior_fit <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 18L,
  burn = 9L,
  thin = 3L,
  seed = 103L,
  kappa = 0.5,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1
)
stopifnot(inherits(alpha_prior_fit, "joint_qvp_qdesn_tiny_fit"))
stopifnot(identical(alpha_prior_fit$alpha_prior_mean_source, "empirical_quantile"))
stopifnot(all(alpha_prior_fit$alpha_prior_sd == 1))
stopifnot(all(is.finite(alpha_prior_fit$alpha_prior_mean)))
stopifnot(all(is.finite(alpha_prior_fit$alpha_draws)))

kappa_fail <- try(app_joint_qvp_fit_al_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 10L,
  burn = 5L,
  kappa = 0
), silent = TRUE)
stopifnot(inherits(kappa_fail, "try-error"))
