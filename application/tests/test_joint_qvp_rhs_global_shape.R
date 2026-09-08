#!/usr/bin/env Rscript

if (!exists("app_joint_qvp_rhs_tau2_shape", mode = "function")) {
  file_arg <- sub(
    "^--file=", "",
    commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]
  )
  repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."), mustWork = TRUE)
  source(file.path(repo_root, "application", "R", "00_packages.R"))
  app_set_repo_root(repo_root)
  source(app_path("application/R/joint_qvp_qdesn.R"))
}

assert_close <- function(observed, expected, label, tolerance = 1.0e-12) {
  difference <- max(abs(as.numeric(observed) - as.numeric(expected)))
  if (!is.finite(difference) || difference > tolerance) {
    stop(sprintf("%s differs by %.12g.", label, difference), call. = FALSE)
  }
}

# The half-Cauchy augmentation tau^2 | xi ~ IG(1/2, 1/xi) adds one-half
# to the p/2 contribution from a p-dimensional Gaussian coefficient block.
stopifnot(identical(app_joint_qvp_rhs_tau2_shape(1L), 1))
stopifnot(identical(app_joint_qvp_rhs_tau2_shape(2L), 1.5))
stopifnot(identical(app_joint_qvp_rhs_tau2_shape(7L), 4))
for (invalid in list(0, -1, 1.5, Inf, NA_real_, c(1, 2))) {
  stopifnot(inherits(try(app_joint_qvp_rhs_tau2_shape(invalid), silent = TRUE), "try-error"))
}

# MCMC: reproduce every inverse-gamma draw under a fixed seed. This checks the
# global shape without depending on a sample moment or a distributional test.
for (block_size in c(1L, 2L, 7L)) {
  block <- app_joint_qvp_initialize_rhs_state(
    K = 1L, p = block_size, tau0 = 0.35, zeta2 = 2.5
  )$anchor
  theta <- seq(0.15, 0.15 * block_size, length.out = block_size)
  seed <- 20260908L + block_size

  set.seed(seed)
  expected_lambda2 <- app_joint_qvp_rinvgamma(
    block_size,
    shape = 1,
    rate = 1 / block$nu + theta^2 / (2 * block$tau2)
  )
  expected_nu <- app_joint_qvp_rinvgamma(
    block_size, shape = 1, rate = 1 + 1 / expected_lambda2
  )
  expected_tau2 <- app_joint_qvp_rinvgamma(
    1,
    shape = (block_size + 1) / 2,
    rate = 1 / block$xi + 0.5 * sum(theta^2 / expected_lambda2)
  )
  expected_xi <- app_joint_qvp_rinvgamma(
    1, shape = 1, rate = 1 / block$tau0^2 + 1 / expected_tau2
  )
  expected_zeta2 <- app_joint_qvp_rinvgamma(
    1,
    shape = block$a_zeta + block_size / 2,
    rate = block$b_zeta + 0.5 * sum(theta^2)
  )

  set.seed(seed)
  observed <- app_joint_qvp_update_rhs_block(block, theta)
  assert_close(observed$lambda2, expected_lambda2, "MCMC local scales")
  assert_close(observed$nu, expected_nu, "MCMC local auxiliaries")
  assert_close(observed$tau2, expected_tau2, "MCMC global scale")
  assert_close(observed$xi, expected_xi, "MCMC global auxiliary")
  assert_close(observed$zeta2, expected_zeta2, "MCMC slab scale")
}

# VB: verify the first coordinate update analytically for several block sizes.
for (block_size in c(1L, 2L, 7L)) {
  block <- app_joint_qvp_initialize_rhs_state(
    K = 1L, p = block_size, tau0 = 0.35, zeta2 = 2.5
  )$anchor
  theta_second <- seq(0.2, 0.2 * block_size, length.out = block_size)
  lambda2_inv <- 1 / block$lambda2
  nu_inv <- 1 / block$nu
  tau2_inv <- 1 / block$tau2
  xi_inv <- 1 / block$xi
  zeta2_inv <- 1 / block$zeta2

  lambda2_rate <- nu_inv + 0.5 * theta_second * tau2_inv
  expected_lambda2_inv <- 1 / lambda2_rate
  expected_nu_inv <- 1 / (1 + expected_lambda2_inv)
  tau2_rate <- xi_inv + 0.5 * sum(theta_second * expected_lambda2_inv)
  expected_tau2_inv <- ((block_size + 1) / 2) / tau2_rate
  expected_xi_inv <- 1 / (1 / block$tau0^2 + expected_tau2_inv)
  expected_zeta2_inv <- (block$a_zeta + block_size / 2) /
    (block$b_zeta + 0.5 * sum(theta_second))

  observed <- app_joint_qvp_update_rhs_vb_block(block, theta_second, n_inner = 1L)
  assert_close(observed$lambda2_inv_mean, expected_lambda2_inv, "VB local precision")
  assert_close(observed$nu_inv_mean, expected_nu_inv, "VB local auxiliary precision")
  assert_close(observed$tau2_inv_mean, expected_tau2_inv, "VB global precision")
  assert_close(observed$xi_inv_mean, expected_xi_inv, "VB global auxiliary precision")
  assert_close(observed$zeta2_inv_mean, expected_zeta2_inv, "VB slab precision")
}

# ELBO accounting: verify that p(tau^2 | xi) and p(xi) both retain their
# IG(1/2, ...) prior shapes, while q(tau^2) has shape (p+1)/2 and q(xi) has
# shape one.
block_size <- 2L
block <- app_joint_qvp_initialize_rhs_state(
  K = 1L, p = block_size, tau0 = 0.35, zeta2 = 2.5
)$anchor
block <- app_joint_qvp_update_rhs_vb_block(block, c(0.2, 0.4), n_inner = 1L)
observed_accounting <- app_joint_qvp_rhs_vb_block_accounting(block, block_size)

ig_log_mean <- function(shape, rate) log(rate) - digamma(shape)
ig_entropy <- function(shape, rate) {
  shape + log(rate) + lgamma(shape) - (shape + 1) * digamma(shape)
}
lambda2_inv <- block$lambda2_inv_mean
nu_inv <- block$nu_inv_mean
tau2_inv <- block$tau2_inv_mean
xi_inv <- block$xi_inv_mean
zeta2_inv <- block$zeta2_inv_mean
lambda_shape <- rep(1, block_size)
lambda_rate <- lambda_shape / lambda2_inv
nu_shape <- rep(1, block_size)
nu_rate <- nu_shape / nu_inv
tau_shape <- (block_size + 1) / 2
tau_rate <- tau_shape / tau2_inv
xi_shape <- 1
xi_rate <- xi_shape / xi_inv
zeta_shape <- block$a_zeta + block_size / 2
zeta_rate <- zeta_shape / zeta2_inv
elog_lambda <- ig_log_mean(lambda_shape, lambda_rate)
elog_nu <- ig_log_mean(nu_shape, nu_rate)
elog_tau <- ig_log_mean(tau_shape, tau_rate)
elog_xi <- ig_log_mean(xi_shape, xi_rate)
elog_zeta <- ig_log_mean(zeta_shape, zeta_rate)

expected_prior <- sum(
  0.5 * (-elog_nu) - lgamma(0.5) -
    1.5 * elog_lambda - nu_inv * lambda2_inv
)
expected_prior <- expected_prior + sum(
  -lgamma(0.5) - 1.5 * elog_nu - nu_inv
)
expected_prior <- expected_prior +
  0.5 * (-elog_xi) - lgamma(0.5) -
    1.5 * elog_tau - xi_inv * tau2_inv
expected_prior <- expected_prior +
  0.5 * log(1 / block$tau0^2) - lgamma(0.5) -
    1.5 * elog_xi - (1 / block$tau0^2) * xi_inv
expected_prior <- expected_prior +
  block$a_zeta * log(block$b_zeta) - lgamma(block$a_zeta) -
    (block$a_zeta + 1) * elog_zeta - block$b_zeta * zeta2_inv
expected_entropy <- sum(ig_entropy(lambda_shape, lambda_rate)) +
  sum(ig_entropy(nu_shape, nu_rate)) +
  ig_entropy(tau_shape, tau_rate) +
  ig_entropy(xi_shape, xi_rate) +
  ig_entropy(zeta_shape, zeta_rate)
expected_log_precision <- 0.5 * sum(log(
  lambda2_inv * tau2_inv + zeta2_inv
))

assert_close(
  observed_accounting$expected_log_scale_prior_kernel,
  expected_prior,
  "VB RHS prior accounting"
)
assert_close(observed_accounting$q_scale_entropy, expected_entropy, "VB RHS entropy")
assert_close(
  observed_accounting$log_precision_approx,
  expected_log_precision,
  "VB RHS log precision"
)

cat("Joint QVP RHS global-scale shape tests passed.\n")
