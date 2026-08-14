#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))

# Constants and the u = B-gamma v identities.
for (tau in c(0.05, 0.5, 0.95)) {
  support <- app_joint_exqdesn_support(tau)
  gamma <- c(0.6 * support$lower[[1L]], -1.0e-5, 0, 1.0e-5, 0.6 * support$upper[[1L]])
  new <- app_joint_exqdesn_constants(tau, gamma)
  old <- do.call(rbind, lapply(gamma, function(g) app_joint_qvp_exal_constants(tau, g)))
  stopifnot(max(abs(new$A - old$A)) < 1.0e-8)
  stopifnot(max(abs(new$B - old$B)) < 1.0e-8)
  stopifnot(max(abs(new$lambda - old$lambda)) < 1.0e-8)
  stopifnot(max(abs(new$A / new$B - new$k)) < 1.0e-12)
  stopifnot(max(abs(new$k^2 + new$p_gamma * (1 - new$p_gamma) - 0.25)) < 1.0e-12)

  p_grid <- sort(unique(c(0.001, tau / 2, tau, tau + (1 - tau) / 2, 0.999)))
  p_grid <- p_grid[p_grid > 0 & p_grid < 1]
  inverse <- app_joint_exqdesn_p_to_gamma(tau, p_grid)
  stopifnot(max(abs(app_joint_exqdesn_gamma_to_p(tau, inverse) - p_grid)) < 1.0e-10)

  gamma_fd <- c(0.35 * support$lower[[1L]], 0.35 * support$upper[[1L]])
  h <- 1.0e-6
  derivative_fd <- vapply(gamma_fd, function(g) {
    (app_joint_exqdesn_gamma_to_p(tau, g + h) - app_joint_exqdesn_gamma_to_p(tau, g - h)) / (2 * h)
  }, numeric(1L))
  stopifnot(max(abs(derivative_fd - app_joint_exqdesn_dp_dgamma(tau, gamma_fd))) < 1.0e-6)
}

set.seed(11)
tau <- 0.1
gamma <- 0.4 * app_joint_exqdesn_support(tau)$upper[[1L]]
cst <- app_joint_exqdesn_constants(tau, gamma)
sigma <- 0.8
s <- 0.7
u <- 1.3
v <- u / cst$B[[1L]]
mu <- -0.2
y <- 0.4
old_joint <- stats::dnorm(
  y,
  mean = mu + sigma * cst$lambda[[1L]] * s + cst$A[[1L]] * v,
  sd = sqrt(sigma * cst$B[[1L]] * v),
  log = TRUE
) + stats::dexp(v, rate = 1 / sigma, log = TRUE) - log(cst$B[[1L]])
new_joint <- stats::dnorm(
  y,
  mean = mu + sigma * cst$lambda[[1L]] * s + cst$k[[1L]] * u,
  sd = sqrt(sigma * u),
  log = TRUE
) + stats::dexp(u, rate = cst$cp[[1L]] / sigma, log = TRUE)
stopifnot(abs(old_joint - new_joint) < 1.0e-12)

# Exact inverse-gamma boundary and sigma-collapse identity.
stopifnot(abs(app_joint_exqdesn_gig_log_integral(-3, 4, 0) + log(4)) < 1.0e-12)
stopifnot(abs(app_joint_exqdesn_gig_moment(-3, 4, 0, 1) - 1) < 1.0e-12)
stopifnot(abs(app_joint_exqdesn_gig_moment(-3, 4, 0, -1) - 1.5) < 1.0e-12)

q <- stats::rnorm(30)
s <- abs(stats::rnorm(30))
u <- stats::rexp(30) + 0.1
stats_u <- app_joint_exqdesn_u_sufficient_stats(q, s, u)
gamma <- 0.25 * app_joint_exqdesn_support(0.5)$upper[[1L]]
terms <- app_joint_exqdesn_u_sigma_gig_terms(gamma, 0.5, stats_u)
collapsed <- app_joint_exqdesn_u_gamma_collapsed_log_kernel(gamma, 0.5, stats_u)
direct <- stats::integrate(
  function(log_sigma) {
    sigma <- exp(log_sigma)
    vapply(seq_along(sigma), function(ii) {
      exp(app_joint_exqdesn_u_log_joint_kernel(sigma[[ii]], gamma, q, s, u, 0.5) + log_sigma[[ii]] - collapsed)
    }, numeric(1L))
  },
  lower = -20,
  upper = 20,
  subdivisions = 1000L,
  rel.tol = 1.0e-9
)$value
stopifnot(abs(direct - 1) < 1.0e-6)
stopifnot(terms$chi > 0, terms$psi >= 0)

# Batched quadrature algebra is identical to the scalar reference algebra.
gamma_grid <- c(
  0.3 * app_joint_exqdesn_support(0.5)$lower[[1L]],
  -1.0e-5,
  1.0e-5,
  0.3 * app_joint_exqdesn_support(0.5)$upper[[1L]]
)
grid_terms <- app_joint_exqdesn_structured_terms_grid(
  gamma_grid, 0.5, "u",
  r_mean = q, r2_mean = q^2 + 0.02,
  latent_mean = u, latent_inv_mean = 1 / u,
  s_mean = s, s2_mean = s^2 + 0.03
)
grid_moments <- app_joint_exqdesn_scale_shape_moments_grid(grid_terms)
for (ii in seq_along(gamma_grid)) {
  scalar_terms <- app_joint_exqdesn_structured_terms(
    gamma_grid[[ii]], 0.5, "u",
    r_mean = q, r2_mean = q^2 + 0.02,
    latent_mean = u, latent_inv_mean = 1 / u,
    s_mean = s, s2_mean = s^2 + 0.03
  )
  stopifnot(max(abs(
    unlist(grid_terms[ii, c("nu", "chi", "psi", "cross", "log_shape", "log_collapsed")]) -
      unlist(scalar_terms[c("nu", "chi", "psi", "cross", "log_shape", "log_collapsed")])
  )) < 1.0e-9)
  scalar_moments <- app_joint_exqdesn_scale_shape_moments(scalar_terms)
  stopifnot(max(abs(
    unlist(grid_moments[ii, names(scalar_moments)]) - scalar_moments
  ) / pmax(1, abs(scalar_moments))) < 1.0e-9)
}

# Branch quadrature agrees after node doubling and returns finite moments.
quadrature <- app_joint_exqdesn_normalize_branch_quadrature(
  tau = 0.5,
  log_density = function(g) app_joint_exqdesn_u_gamma_collapsed_log_kernel(g, 0.5, stats_u),
  moment_function = function(g) c(gamma = g, gamma2 = g^2),
  node_grid = c(4L, 8L, 12L),
  tolerance = 1.0e-5
)
stopifnot(quadrature$converged)
stopifnot(abs(sum(quadrature$branch_mass) - 1) < 1.0e-12)
stopifnot(all(is.finite(quadrature$moments)))

# The branch/logit-p Jacobian reproduces an independent native-gamma integral.
tau_reference <- 0.1
support_reference <- app_joint_exqdesn_support(tau_reference)
reference_mean <- 0.2
reference_sd <- 0.45
reference_quad <- app_joint_exqdesn_normalize_branch_quadrature(
  tau = tau_reference,
  log_density = function(g) stats::dnorm(g, reference_mean, reference_sd, log = TRUE),
  moment_function = function(g) c(gamma = g, gamma2 = g^2),
  node_grid = c(4L, 8L, 12L),
  tolerance = 1.0e-6
)
reference_z <- stats::integrate(
  function(g) stats::dnorm(g, reference_mean, reference_sd),
  support_reference$lower[[1L]], support_reference$upper[[1L]],
  rel.tol = 1.0e-10
)$value
reference_gamma <- stats::integrate(
  function(g) g * stats::dnorm(g, reference_mean, reference_sd),
  support_reference$lower[[1L]], support_reference$upper[[1L]],
  rel.tol = 1.0e-10
)$value / reference_z
reference_gamma2 <- stats::integrate(
  function(g) g^2 * stats::dnorm(g, reference_mean, reference_sd),
  support_reference$lower[[1L]], support_reference$upper[[1L]],
  rel.tol = 1.0e-10
)$value / reference_z
stopifnot(reference_quad$converged)
stopifnot(abs(reference_quad$moments[["gamma"]] - reference_gamma) < 1.0e-6)
stopifnot(abs(reference_quad$moments[["gamma2"]] - reference_gamma2) < 1.0e-6)

# One essential end-to-end API exercise for each new family.
fixture <- app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 24L, tau = 0.5, seed = 2026080601L, innovation = "gaussian"
)
vb <- app_joint_exqdesn_fit_exal_vb_structured(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  augmentation = "u",
  max_iter = 3L,
  tol = 1.0e-4,
  quadrature_nodes = c(4L, 8L),
  quadrature_tolerance = 1.0e-3,
  diagnostic_stride = 1L
)
stopifnot(all(is.finite(vb$qhat_mean)))
stopifnot(all(vb$sigma_mean > 0))
stopifnot(identical(vb$augmentation, "u"))
stopifnot(nrow(vb$scale_shape_summary) == 1L)

mcmc <- app_joint_exqdesn_fit_exal_mcmc_u_collapsed(
  y = fixture$y,
  Z = fixture$Z,
  tau = fixture$tau,
  n_iter = 24L,
  burn = 12L,
  thin = 3L,
  seed = 2026080602L,
  init = vb,
  gamma_coordinate = "p_gamma_logit"
)
stopifnot(all(is.finite(mcmc$beta_draws)))
stopifnot(all(is.finite(mcmc$gamma_draws)))
stopifnot(all(mcmc$sigma_draws > 0))
stopifnot(identical(mcmc$init_source, "provided"))
stopifnot(identical(mcmc$inference_method_id, "M1_u_collapsed_p_logit"))

cat("Exact/structured exQDESN inference tests passed.\n")
