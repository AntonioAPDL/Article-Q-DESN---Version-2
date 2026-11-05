# Pure generated fixtures only: no GloFAS model/data/draw reads or launches.
local({
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_optimizer_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(condition) { stopifnot(isTRUE(condition)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  derivative <- function(fun, x, step = 1e-6) vapply(seq_along(x), function(j) {
    plus <- minus <- x; plus[j] <- plus[j] + step; minus[j] <- minus[j] - step
    (fun(plus) - fun(minus)) / (2 * step)
  }, numeric(1L))
  G <- seq(.08, .22, length.out = 51L)
  m <- c(.12, -2.3); ls <- c(-2.7, -.8)
  factors <- list(diag(2L), matrix(c(1, .6, -.2, 1), 2L))

  for (p in c(.2, .5, .8)) for (L in factors) {
    exact <- gcpor_h1_elbo(m, ls, L, G, p)
    pack <- c(m, ls)
    finite <- derivative(function(x) gcpor_h1_elbo(x[1:2], x[3:4], L, G, p)$value, pack)
    ok(max(abs(finite - exact$gradient)) < 2e-7)
    conditional <- gcpor_h1_conditional_gh_elbo(m, ls, L, G, p, nodes = 32L)
    refined <- gcpor_h1_conditional_gh_elbo(m, ls, L, G, p, nodes = 48L)
    ok(abs(exact$value - conditional$value) < 1e-9 && abs(refined$value - conditional$value) < 1e-9)
    finite2 <- derivative(function(x)
      gcpor_h1_conditional_gh_elbo(x[1:2], x[3:4], L, G, p, nodes = 32L)$value, pack)
    ok(max(abs(finite2 - exact$gradient)) < 2e-7)
    ok(exact$member_factors == 51L && all(exact$member_weights == 1) &&
      exact$original_reads == 0L && !exact$production_qualified)
  }

  # Direct likelihood evaluation in transformed coordinates includes exactly
  # one +eta Jacobian. The wrong no-Jacobian target is explicitly rejected.
  point <- c(.11, log(.07))
  for (p in c(.2, .5)) {
    literal <- stats::dnorm(point[1L], .1, .2, log = TRUE) +
      gcpr_log_ig(exp(point[2L]), 4, .3) + point[2L] +
      sum(gcpr_log_al(G, point[1L], p, exp(point[2L])))
    correct <- gcpor_h1_log_target(point, G, p)
    ok(abs(correct - literal) < 1e-10)
    ok(abs(correct - (literal - point[2L])) > 1)
  }

  # A no-member normalized future law contributes zero; both parameters
  # remain random. Recovery here is the exact Gaussian-family optimum, NOT
  # equality of a log-Normal sigma approximation to an inverse-gamma prior.
  m0 <- c(.1, log(.3 / 4) + 1 / 8); ls0 <- c(log(.2), -.5 * log(4))
  no_members <- gcpor_h1_elbo(m0, ls0)
  ok(max(abs(no_members$gradient)) < 1e-12)
  ok(no_members$value < 0 && no_members$member_factors == 0L)
  quadrature <- gcpor_gaussian_gh(gcpor_h1_log_target, m0, ls0, nodes = 24L)
  ok(abs(quadrature$value - no_members$value) < 1e-11 && max(abs(quadrature$gradient)) < 1e-10)
  coarse <- gcpor_gaussian_gh(gcpor_h1_log_target, m0, ls0, nodes = 16L)
  ok(abs(coarse$value - quadrature$value) < 1e-10)
  fit0 <- gcpor_h1_optimize(c(.3, -1.5), c(-1, -.3))
  ok(fit0$convergence == 0L && max(abs(c(fit0$mean - m0, fit0$log_sd - ls0))) < 2e-5)
  ok(abs(fit0$value - no_members$value) < 1e-9 && fit0$value > fit0$initial_value)
  q0 <- gcpor_gaussian_physical_moments(m0, ls0)
  exact0 <- gcpor_h1_joint_moments()
  ok(abs(q0$theta_mean - exact0$mean[1L]) < 1e-10 &&
    abs(q0$theta_variance - exact0$covariance[1L, 1L]) < 1e-10)
  ok(abs(exact0$mean[2L] - (log(.3) - digamma(4))) < 1e-9 &&
    abs(exact0$covariance[2L, 2L] - trigamma(4)) < 1e-9)
  ok(abs(q0$sigma_mean - .3 / 4 * exp(1 / 4)) < 1e-12 &&
    abs(q0$sigma_mean - exact0$sigma_mean) > .003)
  ok(abs(q0$sigma_cdf(.1) - exact0$sigma_cdf(.1)) > .005)

  # The fixed-factor formulation can represent a specified correlated Normal
  # exactly. This does not imply that the optimizer learns arbitrary factors.
  target_mean <- c(-.2, .4); target_cov <- matrix(c(.3, .12, .12, .7), 2L)
  L <- t(chol(target_cov)); inverse <- solve(target_cov)
  log_normal <- function(x) -log(2 * pi) - .5 * as.numeric(determinant(target_cov,
    logarithm = TRUE)$modulus) - .5 * sum((x - target_mean) * (inverse %*% (x - target_mean)))
  normal_exact <- gcpor_gaussian_gh(log_normal, target_mean, c(0, 0), L, nodes = 16L)
  ok(abs(normal_exact$value) < 1e-12 && max(abs(normal_exact$gradient)) < 1e-12)
  normal_off <- gcpor_gaussian_gh(log_normal, c(.1, .1), c(-.3, .2), L, nodes = 16L)
  normal_fd <- derivative(function(x) gcpor_gaussian_gh(log_normal, x[1:2], x[3:4], L,
    nodes = 16L)$value, c(.1, .1, -.3, .2))
  ok(max(abs(normal_off$gradient - normal_fd)) < 1e-8)

  # All 51 unit member factors legitimately update both parameter marginals.
  # Their posterior dependence remains present in the exact reference.
  concentrated <- rep(.2, 51L)
  truth <- gcpor_h1_joint_moments(concentrated, probability = .2)
  ok(abs(truth$mean[1L] - exact0$mean[1L]) > .05 &&
    abs(truth$mean[2L] - exact0$mean[2L]) > .5)
  ok(abs(truth$covariance[1L, 2L]) > 1e-6 &&
    all(eigen(truth$covariance, symmetric = TRUE)$values > 0))
  fit <- gcpor_h1_optimize(m0, ls0, members = concentrated, probability = .2)
  ok(fit$convergence == 0L && max(abs(fit$gradient)) < .001 && fit$value > fit$initial_value)
  ok(fit$value <= truth$log_evidence + 1e-8)
  physical <- gcpor_gaussian_physical_moments(fit$mean, fit$log_sd)
  ok(physical$theta_sigma_covariance == 0 && abs(truth$theta_sigma_covariance) > 1e-8)
  ok(max(abs(c(physical$sigma_cdf(.005), physical$sigma_cdf(.01)) -
    truth$sigma_cdf(c(.005, .01)))) > 1e-4)
  ok(all(diff(truth$future_cdf(c(-Inf, .15, .2, .3, Inf))) > 0) &&
    truth$future_cdf(Inf) == 1 && !truth$production_qualified)

  # H2 references test the complete parameter dependence. Integrating Y2 out
  # does not remove the Y1 law from the later-member likelihood gradient.
  H2 <- matrix(c(.15, .22), 2L, 1L)
  for (lag in c(-.35, .35)) {
    conditional <- gcpr_conditional(point[1L], exp(point[2L]), H2, p = .2, lag = lag)
    density <- function(x) gcpor_h1_log_target(x) +
      gcpr_conditional(x[1L], exp(x[2L]), H2, p = .2, lag = lag)$log_evidence
    prior_gradient <- c(- (point[1L] - .1) / .2^2, -4 + .3 * exp(-point[2L]))
    ok(max(abs(derivative(density, point) - prior_gradient - conditional$fisher_gradient)) < 1e-6)
    biased <- gcpr_log_bound_one_particle(point[1L], exp(point[2L]), H2, p = .2, lag = lag)
    ok(biased$Jensen_gap > 0 && biased$expected_log_estimate < biased$exact_log_evidence)
  }
  gap1 <- gcpr_log_bound_one_particle(.1, .07, H2, p = .2)$Jensen_gap
  gap2 <- gcpr_log_bound_one_particle(.1, .2, H2, p = .2)$Jensen_gap
  ok(abs(gap1 - gap2) > 1e-3) # A parameter-dependent finite-N bound, not exact log Z.

  reject(gcpor_h1_elbo(m, ls, members = rep(.1, 50L)))
  reject(gcpor_h1_elbo(m, ls, probability = 1))
  reject(gcpor_h1_elbo(m, ls, shape = 2))
  reject(gcpor_h1_elbo(m, ls, factor = matrix(1, 2L, 2L)))
  reject(gcpor_h1_elbo(m, c(-20, -1)))
  reject(gcpor_h1_log_target(c(.1, Inf)))
  reject(gcpor_normal_quadrature(65L))
  reject(gcpor_gaussian_gh(function(x) NA_real_, m, ls))
  reject(gcpor_gaussian_gh(function(x) 0, rep(0, 3L), rep(0, 3L), nodes = 64L))
  reject(gcpor_h1_optimize(m, ls, max_iterations = 1001L))
  cat(sprintf("GloFAS collapsed optimizer independent reference: %d checks PASS\n", checks))
})
