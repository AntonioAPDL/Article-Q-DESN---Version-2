# Independent generated-target variational references. These functions do not
# load application data, fit the GloFAS model, or qualify a production method.
# eta denotes log(sigma); all targets below are densities in (theta, eta).

gcpor_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("Collapsed optimizer reference: ", why), call. = FALSE)
}

gcpor_gaussian_contract <- function(mean, log_sd, factor = diag(length(mean))) {
  p <- length(mean)
  gcpor_require(is.numeric(mean) && p %in% 1:3 && is.numeric(log_sd) &&
    length(log_sd) == p && all(is.finite(c(mean, log_sd))) &&
    all(abs(mean) <= 100) && all(log_sd >= -12 & log_sd <= 2),
    "bounded finite generated Gaussian parameters required")
  gcpor_require(is.matrix(factor) && is.numeric(factor) &&
    identical(dim(factor), c(p, p)) && all(is.finite(factor)) &&
    max(abs(factor)) <= 100 && rcond(factor) > 1e-10,
    "bounded invertible fixed Gaussian factor required")
  covariance <- tcrossprod(sweep(factor, 2L, exp(log_sd), "*"))
  gcpor_require(all(is.finite(covariance)) && !inherits(try(chol(covariance),
    silent = TRUE), "try-error"), "positive-definite covariance required")
  list(mean = mean, log_sd = log_sd, factor = factor, covariance = covariance,
    entropy = p / 2 * log(2 * pi * exp(1)) + sum(log_sd) +
      as.numeric(determinant(factor, logarithm = TRUE)$modulus), p = p)
}

gcpor_h1_contract <- function(members, probability, prior_mean, prior_sd, shape, rate) {
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  gcpor_require(is.numeric(members) && length(members) %in% c(0L, 1L, 51L) &&
    all(is.finite(members)) && all(vapply(list(probability, prior_mean, prior_sd,
      shape, rate), scalar, logical(1L))) && probability > 0 && probability < 1 &&
    prior_sd > 0 && shape > 2 && rate > 0,
    "proper scalar Normal/IG target with zero, one or 51 unit members required")
  invisible(TRUE)
}

gcpor_expected_rho <- function(residual_mean, residual_sd, probability) {
  gcpor_require(all(is.finite(residual_mean)) && length(residual_sd) == 1L &&
    is.finite(residual_sd) && residual_sd > 0 && probability > 0 && probability < 1,
    "finite Normal residuals and interior quantile probability required")
  z <- residual_mean / residual_sd
  residual_sd * stats::dnorm(z) + residual_mean * (probability - stats::pnorm(-z))
}

gcpor_h1_elbo <- function(mean, log_sd, factor = diag(2L), members = numeric(),
    probability = .5, prior_mean = .1, prior_sd = .2, shape = 4, rate = .3) {
  q <- gcpor_gaussian_contract(mean, log_sd, factor)
  gcpor_require(q$p == 2L, "theta and log(sigma) must both be uncertain")
  gcpor_h1_contract(members, probability, prior_mean, prior_sd, shape, rate)
  V <- q$covariance; mt <- mean[1L]; me <- mean[2L]
  # Normal exponential tilting: the coefficient's tilted mean is mt - V12.
  # This retains theta/eta dependence instead of multiplying marginal means.
  e <- members - mt + V[1L, 2L]; s <- sqrt(V[1L, 1L]); z <- e / s
  S <- sum(gcpor_expected_rho(e, s, probability))
  D <- sum(probability - stats::pnorm(-z))
  B <- sum(stats::dnorm(z) / (2 * s))
  T <- exp(-me + V[2L, 2L] / 2)
  prior_variance <- prior_sd^2; M <- length(members)
  value <- -.5 * log(2 * pi * prior_variance) -
    ((mt - prior_mean)^2 + V[1L, 1L]) / (2 * prior_variance) +
    shape * log(rate) - lgamma(shape) + M * log(probability * (1 - probability)) -
    (shape + M) * me - T * (rate + S) + q$entropy
  gradient_mean <- c(-(mt - prior_mean) / prior_variance + T * D,
    -(shape + M) + T * (rate + S))
  # Derivatives in the unique covariance coordinates V11, V22, V12.
  g11 <- -.5 / prior_variance - T * B
  g22 <- -.5 * T * (rate + S); g12 <- -T * D
  gradient_log_sd <- 1 + 2 * exp(2 * log_sd) *
    (g11 * factor[1L, ]^2 + g22 * factor[2L, ]^2 +
      g12 * factor[1L, ] * factor[2L, ])
  gradient <- c(gradient_mean, gradient_log_sd)
  gcpor_require(all(is.finite(c(value, gradient))), "nonfinite exact ELBO or gradient")
  list(value = value, gradient = gradient, covariance = V, entropy = q$entropy,
    member_factors = M, member_weights = rep(1, M),
    coordinate_measure = "dtheta dlog_sigma; inverse-gamma transformation Jacobian included once",
    integration = "analytic Gaussian exponential tilt and expected AL check loss",
    original_reads = 0L, production_qualified = FALSE)
}

gcpor_normal_quadrature <- function(nodes = 24L) {
  gcpor_require(is.numeric(nodes) && length(nodes) == 1L && is.finite(nodes) &&
    nodes == floor(nodes) && nodes >= 8 && nodes <= 64,
    "8--64 standard-Normal quadrature nodes required")
  nodes <- as.integer(nodes); k <- seq_len(nodes - 1L); J <- matrix(0, nodes, nodes)
  J[cbind(k, k + 1L)] <- J[cbind(k + 1L, k)] <- sqrt(k)
  e <- eigen(J, symmetric = TRUE)
  list(nodes = e$values, weights = e$vectors[1L, ]^2)
}

gcpor_gaussian_gh <- function(log_density, mean, log_sd,
    factor = diag(length(mean)), nodes = 24L) {
  q <- gcpor_gaussian_contract(mean, log_sd, factor)
  gcpor_require(is.function(log_density), "pure generated log-density callback required")
  z <- gcpor_normal_quadrature(nodes)
  gcpor_require(nodes^q$p <= 100000L, "tensor quadrature budget exceeded")
  indices <- as.matrix(expand.grid(rep(list(seq_len(nodes)), q$p)))
  epsilon <- matrix(z$nodes[indices], nrow(indices), q$p)
  w <- apply(matrix(z$weights[indices], nrow(indices), q$p), 1L, prod)
  points <- sweep(sweep(epsilon, 2L, exp(log_sd), "*") %*% t(factor), 2L, mean, "+")
  reward <- apply(points, 1L, function(point) {
    value <- log_density(as.numeric(point))
    gcpor_require(is.numeric(value) && length(value) == 1L && is.finite(value),
      "generated density must return one finite log density")
    value
  })
  expectation <- sum(w * reward)
  score_mean <- sweep(epsilon, 2L, exp(log_sd), "/") %*% solve(factor)
  score_sd <- epsilon^2 - 1
  centered <- w * (reward - expectation)
  gradient <- c(colSums(sweep(score_mean, 1L, centered, "*")),
    colSums(sweep(score_sd, 1L, centered, "*")) + 1)
  list(value = expectation + q$entropy, gradient = gradient,
    expected_log_density = expectation, entropy = q$entropy,
    nodes_per_dimension = nodes, density_evaluations = nrow(indices),
    integration = "deterministic tensor standard-Normal quadrature; require node comparison",
    original_reads = 0L, production_qualified = FALSE)
}

gcpor_h1_conditional_gh_elbo <- function(mean, log_sd, factor = diag(2L),
    members = numeric(), probability = .5, prior_mean = .1, prior_sd = .2,
    shape = 4, rate = .3, nodes = 32L) {
  q <- gcpor_gaussian_contract(mean, log_sd, factor)
  gcpor_require(q$p == 2L, "joint theta/log-scale Gaussian required")
  gcpor_h1_contract(members, probability, prior_mean, prior_sd, shape, rate)
  z <- gcpor_normal_quadrature(nodes); V <- q$covariance
  conditional_variance <- V[1L, 1L] - V[1L, 2L]^2 / V[2L, 2L]
  gcpor_require(conditional_variance > 0, "nondegenerate conditional Normal required")
  eta <- mean[2L] + sqrt(V[2L, 2L]) * z$nodes
  theta_mean <- mean[1L] + V[1L, 2L] / sqrt(V[2L, 2L]) * z$nodes
  conditional_loss <- vapply(seq_along(eta), function(i)
    sum(gcpor_expected_rho(members - theta_mean[i], sqrt(conditional_variance), probability)),
    numeric(1L))
  expectation <- sum(z$weights * exp(-eta) * (rate + conditional_loss))
  value <- -.5 * log(2 * pi * prior_sd^2) -
    ((mean[1L] - prior_mean)^2 + V[1L, 1L]) / (2 * prior_sd^2) +
    shape * log(rate) - lgamma(shape) +
    length(members) * log(probability * (1 - probability)) -
    (shape + length(members)) * mean[2L] - expectation + q$entropy
  gcpor_require(is.finite(value), "nonfinite conditional quadrature result")
  list(value = value, nodes = nodes, original_reads = 0L, production_qualified = FALSE)
}

gcpor_h1_log_target <- function(point, members = numeric(), probability = .5,
    prior_mean = .1, prior_sd = .2, shape = 4, rate = .3) {
  gcpor_h1_contract(members, probability, prior_mean, prior_sd, shape, rate)
  gcpor_require(is.numeric(point) && length(point) == 2L && all(is.finite(point)) &&
    abs(point[2L]) < 300, "finite theta/log-scale point required")
  theta <- point[1L]; eta <- point[2L]
  loss <- sum((members - theta) * (probability - (members < theta)))
  # The IG sigma density contributes -(a+1)*eta; the +eta Jacobian is
  # included exactly once here, leaving -a*eta before member contributions.
  stats::dnorm(theta, prior_mean, prior_sd, log = TRUE) + shape * log(rate) -
    lgamma(shape) - (shape + length(members)) * eta -
    exp(-eta) * (rate + loss) + length(members) * log(probability * (1 - probability))
}

gcpor_h1_optimize <- function(initial_mean, initial_log_sd, factor = diag(2L),
    members = numeric(), probability = .5, prior_mean = .1, prior_sd = .2,
    shape = 4, rate = .3, max_iterations = 500L) {
  gcpor_require(length(max_iterations) == 1L && is.finite(max_iterations) &&
    max_iterations == floor(max_iterations) && max_iterations >= 1 && max_iterations <= 1000,
    "1--1000 generated-reference optimization iterations required")
  evaluate <- function(x) gcpor_h1_elbo(x[1:2], x[3:4], factor, members,
    probability, prior_mean, prior_sd, shape, rate)
  initial <- c(initial_mean, initial_log_sd); start <- evaluate(initial)$value
  fit <- stats::optim(initial, function(x) -evaluate(x)$value,
    function(x) -evaluate(x)$gradient, method = "L-BFGS-B", lower = c(-10, -20, -12, -12),
    upper = c(10, 10, 2, 2), control = list(maxit = max_iterations, factr = 100, pgtol = 1e-8))
  value <- evaluate(fit$par)
  list(mean = fit$par[1:2], log_sd = fit$par[3:4], value = value$value,
    gradient = value$gradient, covariance = value$covariance,
    initial_value = start, convergence = fit$convergence, message = fit$message,
    evaluations = fit$counts, original_reads = 0L, production_qualified = FALSE,
    scope = "exact generated-target optimum within specified fixed-factor Gaussian family")
}

gcpor_h1_joint_moments <- function(members = numeric(), probability = .5,
    prior_mean = .1, prior_sd = .2, shape = 4, rate = .3) {
  gcpor_h1_contract(members, probability, prior_mean, prior_sd, shape, rate)
  gcpor_require(exists("gcpr_one_horizon_joint_scale", mode = "function"),
    "source the independent collapsed-particle reference first")
  exact <- gcpr_one_horizon_joint_scale(members, probability, prior_mean, prior_sd, shape, rate)
  A <- exact$conditional_sigma_shape; B <- exact$conditional_sigma_rate
  cuts <- sort(unique(c(-Inf, members, prior_mean, exact$theta_mean, Inf)))
  integrate <- function(fun) sum(vapply(seq_len(length(cuts) - 1L), function(i)
    stats::integrate(fun, cuts[i], cuts[i + 1L], rel.tol = 1e-9,
      abs.tol = 1e-11, subdivisions = 1000L)$value, numeric(1L)))
  density <- exact$parameter_density
  me <- integrate(function(t) (log(B(t)) - digamma(A)) * density(t))
  ve <- trigamma(A) + integrate(function(t) (log(B(t)) - digamma(A) - me)^2 * density(t))
  cross <- integrate(function(t) (t - exact$theta_mean) * (log(B(t)) - digamma(A) - me) * density(t))
  sigma_cdf <- function(s) {
    gcpor_require(is.numeric(s) && !anyNA(s), "numeric nonmissing scale CDF arguments required")
    vapply(s, function(value) {
    if (value <= 0) return(0)
    if (is.infinite(value)) return(1)
    integrate(function(t) stats::pgamma(1 / value, shape = A, rate = B(t),
      lower.tail = FALSE) * density(t))
    }, numeric(1L))
  }
  list(mean = c(theta = exact$theta_mean, log_sigma = me),
    covariance = matrix(c(exact$theta_variance, cross, cross, ve), 2L),
    sigma_mean = exact$sigma_mean, sigma_variance = exact$sigma_variance,
    theta_sigma_covariance = exact$theta_sigma_covariance,
    log_evidence = exact$log_evidence, sigma_cdf = sigma_cdf,
    future_cdf = exact$future_cdf, member_factors = length(members),
    original_reads = 0L, production_qualified = FALSE)
}

gcpor_gaussian_physical_moments <- function(mean, log_sd, factor = diag(2L)) {
  q <- gcpor_gaussian_contract(mean, log_sd, factor)
  gcpor_require(q$p == 2L, "theta and log-scale moments required")
  V <- q$covariance; ms <- exp(mean[2L] + V[2L, 2L] / 2)
  list(theta_mean = mean[1L], theta_variance = V[1L, 1L], sigma_mean = ms,
    sigma_variance = ms^2 * expm1(V[2L, 2L]), theta_sigma_covariance = V[1L, 2L] * ms,
    sigma_cdf = function(s) stats::plnorm(s, meanlog = mean[2L], sdlog = sqrt(V[2L, 2L])),
    original_reads = 0L, production_qualified = FALSE)
}
