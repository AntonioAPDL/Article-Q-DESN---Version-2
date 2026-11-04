# Generated calculations only. This test does not admit authentic model reads
# or qualify a nonlinear, uncertain-parameter, exAL or MQ production method.
local({
  source("scripts/diagnostics/glofas_collapsed_gaussian_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_fixed_target_smoothing_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(condition) {stopifnot(isTRUE(condition)); checks <<- checks + 1L}
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  rho <- function(y, p) y * (p - (y < 0))
  # Independent integration in standard-Normal coordinates, split at the
  # check-loss kink. No expected-check-loss formula is reused here.
  numerical_expected_loss <- function(e, s, p) {
    cut <- -e / s
    integrand <- function(z) rho(e + s * z, p) * stats::dnorm(z)
    sum(vapply(list(c(-Inf, cut), c(cut, Inf)), function(b)
      stats::integrate(integrand, b[1L], b[2L], rel.tol = 1e-11, abs.tol = 1e-12)$value, numeric(1L)))
  }
  al_cdf <- function(y, mu, p, sigma) {
    r <- (y - mu) / sigma
    ifelse(r < 0, p * exp((1 - p) * r), 1 - (1 - p) * exp(-p * r))
  }
  scalar <- list(); accuracy <- list(); index <- 0L
  for (p in c(.05, .20, .35, .50, .65, .80, .95)) for (sigma in c(.07, .7, 2)) {
    index <- index + 1L; mu <- .37
    analytic <- gcgr_single_al_optimum(p, sigma, mu)
    e <- analytic$mean - mu; s <- analytic$sd
    ok(abs(gcgr_expected_check_loss(e, s, p) - numerical_expected_loss(e, s, p)) < 1e-9 * max(1, sigma))
    c <- gcgr_affine_contract(matrix(1), offset = -mu, p = p, scale = sigma)
    objective <- gcgr_affine_objective(analytic$mean, matrix(s^2), c)
    ok(max(abs(c(objective$mean_gradient * sigma, objective$covariance_gradient * sigma^2))) < 1e-10)
    # Optimize a separately integrated objective in normalized coordinates
    # from a nonoptimal, p-independent start. The independent optimizer uses
    # derivative-free simplex search, not the analytic candidate gradients.
    independent <- stats::optim(c(.25, log(.8)), function(b)
      numerical_expected_loss(b[1L], exp(b[2L]), p) - b[2L], method = "Nelder-Mead",
      control = list(reltol = 1e-13, maxit = 2000L))
    ok(independent$convergence == 0L)
    ok(max(abs(c(independent$par[1L] - e / sigma,
      exp(independent$par[2L]) - s / sigma))) < 2e-5)
    qp <- stats::qnorm(p, analytic$mean, s)
    ok(abs(qp - mu) < 1e-11 * max(1, sigma))
    ok(abs(stats::pnorm(mu, analytic$mean, s) - p) < 1e-14 &&
      abs(al_cdf(mu, mu, p, sigma) - p) < 1e-14)
    ok(is.finite(analytic$collapsed_KL) && analytic$collapsed_KL > .01)
    grid <- mu + sigma * c(-10, -3, -1, 0, 1, 3, 10)
    discrepancy <- max(abs(stats::pnorm(grid, analytic$mean, s) - al_cdf(grid, mu, p, sigma)))
    ok(discrepancy > .01)
    scalar[[index]] <- data.frame(p = p, sigma = sigma, mean = analytic$mean, sd = s,
      selected_quantile_error = abs(qp - mu), maximum_checked_CDF_error = discrepancy,
      Gaussian_KL_to_AL = analytic$collapsed_KL)
    accuracy[[index]] <- data.frame(case = paste("scalar", p, sigma),
      reference_validity = "PASS", software_derivatives = "PASS",
      selected_probability_accuracy = "PASS", full_distribution_accuracy = "FAIL",
      interpretation = "one quantile is exact; Gaussian still differs from AL")
  }
  # Direct finite differences of the independently expanded literal factor
  # sum. Covariance off-diagonal perturbations are symmetric, hence 2*G12.
  contract <- gcgr_affine_contract(rbind(c(1, 0), c(-.3, 1), c(-.2, .1), c(0, 0)),
    offset = c(-.2, .15, -.1, .3), p = .2, scale = c(.7, 1.1, .4, .5))
  m <- c(.15, -.25); V <- matrix(c(.8, .12, .12, .6), 2L)
  literal <- function(mm, VV) sum(vapply(seq_len(nrow(contract$A)), function(i) {
    a <- contract$A[i, ]; e <- contract$offset[i] + sum(a * mm)
    s <- sqrt(as.numeric(a %*% VV %*% a))
    (if (s == 0) rho(e, contract$p[i]) else numerical_expected_loss(e, s, contract$p[i])) / contract$scale[i]
  }, numeric(1L))) - .5 * as.numeric(determinant(VV, logarithm = TRUE)$modulus)
  obj <- gcgr_affine_objective(m, V, contract); step <- 1e-5
  ok(abs(obj$value - literal(m, V)) < 1e-10)
  for (j in 1:2) {
    direction <- rep(0, 2); direction[j] <- step
    numerical <- (literal(m + direction, V) - literal(m - direction, V)) / (2 * step)
    ok(abs(numerical - obj$mean_gradient[j]) < 1e-7)
  }
  for (ij in list(c(1L, 1L), c(2L, 2L), c(1L, 2L))) {
    d <- matrix(0, 2, 2); d[ij[1L], ij[2L]] <- step; d[ij[2L], ij[1L]] <- step
    numerical <- (literal(m, V + d) - literal(m, V - d)) / (2 * step)
    expected <- obj$covariance_gradient[ij[1L], ij[2L]] * if (ij[1L] == ij[2L]) 1 else 2
    ok(abs(numerical - expected) < 1e-7)
  }
  # H1 and H2 Gaussian entropy use log(det(V))/2, not log(sd) per
  # augmented local variable. Every future member has one ordinary factor.
  one <- gcgr_affine_contract(matrix(1), -.37, .2, .7)
  one_fit <- gcgr_affine_optimize(one)
  one_exact <- gcgr_single_al_optimum(.2, .7, .37)
  ok(one_fit$status == "GENERATED_COLLAPSED_GAUSSIAN_STATIONARY")
  ok(max(abs(c(one_fit$mean - one_exact$mean, sqrt(one_fit$covariance[1L]) - one_exact$sd))) < 2e-6)
  smoothing <- list()
  for (members in c(1L, 51L)) {
    c <- gcgr_smoothing_contract(members)
    fit <- gcgr_affine_optimize(c, initial_mean = c(if (members == 1L) -.05 else -1.9, 0),
      initial_covariance = diag(c(.01, .03)))
    exact <- gftsr_contract(members)
    probabilities <- c(.05, .20, .35, .50, .65, .80, .95)
    exact_quantiles <- vapply(probabilities, gftsr_quantile, numeric(1L), contract = exact)
    approximation_quantiles <- stats::qnorm(probabilities, fit$mean[1L], sqrt(fit$covariance[1L, 1L]))
    cdf_errors <- abs(gftsr_piecewise_cdf(approximation_quantiles, exact) - probabilities)
    ok(fit$status == "GENERATED_COLLAPSED_GAUSSIAN_STATIONARY")
    ok(all(c$factor_weights == 1) && nrow(c$A) == 2L + 2L * members)
    ok(max(abs(gftsr_piecewise_cdf(exact_quantiles, exact) - probabilities)) < 1e-8)
    ok(abs(fit$covariance[1L, 2L]) < 1e-7 && abs(fit$mean[2L]) < 1e-10)
    ok(max(cdf_errors) > .01)
    smoothing[[as.character(members)]] <- data.frame(n_members = members, probability = probabilities,
      exact_quantile = exact_quantiles, collapsed_Gaussian_quantile = approximation_quantiles,
      exact_CDF_at_Gaussian_quantile = gftsr_piecewise_cdf(approximation_quantiles, exact),
      approximation_accuracy = ifelse(cdf_errors <= 1e-3, "PASS", "FAIL"))
  }
  # A joint theta,Y Gaussian may retain the exact no-future-observation
  # parameter posterior. The independent future block instead shrinks it.
  normals <- list()
  for (variance in c(.1, .8, 2)) for (dimension in 1:2) {
    mu <- c(.4, -.2)[seq_len(dimension)]
    V0 <- if (dimension == 1L) matrix(1.1) else matrix(c(1.1, .2, .2, .7), 2L)
    x <- c(1, -.4)[seq_len(dimension)]
    a <- gcgr_normal_coupled_reference(mu, V0, x, variance)
    ok(max(abs(a$covariance - a$covariance_from_independent_residual)) < 1e-14)
    ok(identical(unname(a$coefficient_marginal_covariance), unname(V0)))
    ok(max(abs(a$theta_future_cross_covariance - as.numeric(V0 %*% x))) < 1e-14)
    ok(abs(a$coupled_KL) < 1e-12 && a$independent_future_block_KL > .01)
    ok(abs(a$independent_future_block_KL - a$closed_form_independent_KL) < 1e-12)
    ok(min(eigen(V0 - a$independent_future_block_theta_covariance, symmetric = TRUE)$values) > -1e-12)
    # Independent Gaussian density evaluation versus prior times normalized
    # future density; this verifies the triangular-coordinate construction.
    for (theta in list(mu, mu + .3)) {
      y <- sum(x * theta) + .2
      delta <- theta - mu
      log_prior <- -.5 * (dimension * log(2 * pi) + as.numeric(determinant(V0, logarithm = TRUE)$modulus) +
        as.numeric(crossprod(delta, solve(V0, delta))))
      joint <- c(theta, y) - a$mean
      log_joint <- -.5 * ((dimension + 1L) * log(2 * pi) +
        as.numeric(determinant(a$covariance, logarithm = TRUE)$modulus) +
        as.numeric(crossprod(joint, solve(a$covariance, joint))))
      ok(abs(log_joint - log_prior - stats::dnorm(y, sum(x * theta), sqrt(variance), log = TRUE)) < 1e-12)
      ok(abs(stats::integrate(function(yy) stats::dnorm(yy, sum(x * theta), sqrt(variance)),
        -Inf, Inf, rel.tol = 1e-10)$value - 1) < 1e-10)
    }
    normals[[paste(variance, dimension)]] <- a
  }
  reject(gcgr_single_al_optimum(0))
  reject(gcgr_expected_check_loss(1, -1, .5))
  reject(gcgr_affine_contract(matrix(0, 1, 1)))
  reject(gcgr_affine_contract(diag(3)))
  reject(gcgr_affine_objective(m, matrix(1, 2, 2), contract))
  reject(gcgr_normal_coupled_reference(observation_variance = -1))
  scalar <- do.call(rbind, scalar); accuracy <- do.call(rbind, accuracy)
  smoothing <- do.call(rbind, smoothing)
  stopifnot(nrow(scalar) == 21L, sum(accuracy$full_distribution_accuracy == "FAIL") == 21L,
    any(smoothing$approximation_accuracy == "FAIL"))
  cat(sprintf("GLOFAS_COLLAPSED_GAUSSIAN_REFERENCE_PASS checks=%d scalar_cases=%d full_distribution_failures=%d smoothing_quantile_failures=%d original_reads=0 full_parameter_refits=0\n",
    checks, nrow(scalar), sum(accuracy$full_distribution_accuracy == "FAIL"), sum(smoothing$approximation_accuracy == "FAIL")))
})
