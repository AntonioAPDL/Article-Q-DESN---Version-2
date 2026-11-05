# Controlled marginal-AL references. No application payload or fitting driver
# is accessed. The H2 reference varies theta and the future AL scale with a
# fixed member scale; the H1 reference has a jointly uncertain shared scale.
# Recurrent coefficients and proper Normal-prior hyperparameters are fixed.
# This is not a complete RHS/exAL/MQ/nonlinear-application qualification.

gcpr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("Collapsed-particle reference: ", why), call. = FALSE)
}

gcpr_rho <- function(e, p) e * (p - (e < 0))

gcpr_log_al <- function(y, location, p, scale) {
  log(p * (1 - p) / scale) - gcpr_rho(y - location, p) / scale
}

gcpr_contract <- function(theta, sigma, members = NULL, p = .5, member_scale = .8,
                          lag = .35, horizon = 2L) {
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  gcpr_require(all(vapply(list(theta, sigma, p, member_scale, lag), scalar, logical(1L))) &&
    sigma > 0 && member_scale > 0 && p > 0 && p < 1 && horizon %in% 1:2,
    "finite fixed theta, positive scales and one/two horizons required")
  if (is.null(members)) members <- matrix(numeric(), as.integer(horizon), 0L)
  gcpr_require(is.matrix(members) && is.numeric(members) && nrow(members) == horizon &&
    ncol(members) %in% c(0L, 1L, 51L) && all(is.finite(members)),
    "zero, one or all 51 finite members per horizon required")
  list(theta = theta, sigma = sigma, members = members, p = p,
    member_scale = member_scale, lag = lag, horizon = as.integer(horizon))
}

gcpr_piecewise <- function(a, b, scales, p) {
  # Each normalized factor is AL_p(a_i*y+b_i;0,scale_i). The product is
  # piecewise exponential. Every interval mass and first moment is analytic.
  gcpr_require(length(a) == length(b) && length(a) == length(scales) &&
    all(is.finite(c(a, b, scales))) && all(scales > 0) && any(a != 0),
    "finite proper affine AL product required")
  knots <- sort(unique(-b[a != 0] / a[a != 0]))
  log_kernel <- function(y) vapply(y, function(z)
    sum(log(p * (1 - p) / scales) - gcpr_rho(a * z + b, p) / scales), numeric(1L))
  peak <- max(log_kernel(knots))
  boundaries <- c(-Inf, knots, Inf)
  out <- lapply(seq_len(length(boundaries) - 1L), function(i) {
    lo <- boundaries[i]; hi <- boundaries[i + 1L]
    point <- if (!is.finite(lo)) hi - 1 else if (!is.finite(hi)) lo + 1 else (lo + hi) / 2
    rate <- -sum(a * (p - (a * point + b < 0)) / scales)
    if (!is.finite(lo)) {
      gcpr_require(rate > 0, "improper left tail")
      mass <- exp(log_kernel(hi) - peak) / rate; mean <- hi - 1 / rate
    } else if (!is.finite(hi)) {
      gcpr_require(rate < 0, "improper right tail")
      mass <- exp(log_kernel(lo) - peak) / (-rate); mean <- lo - 1 / rate
    } else {
      width <- hi - lo; z <- abs(rate) * width
      if (z < 1e-5) {
        # Stable first moment of a nearly uniform truncated exponential.
        distance <- width / 2 - abs(rate) * width^2 / 12 + abs(rate)^3 * width^4 / 720
      } else distance <- 1 / abs(rate) - width / expm1(z)
      if (rate > 0) {
        mass <- exp(log_kernel(hi) - peak) * (-expm1(-z)) / rate
        mean <- hi - distance
      } else if (rate < 0) {
        mass <- exp(log_kernel(lo) - peak) * (-expm1(-z)) / (-rate)
        mean <- lo + distance
      } else { mass <- exp(log_kernel(lo) - peak) * width; mean <- point }
    }
    data.frame(lower = lo, upper = hi, point = point, rate = rate,
      relative_mass = mass, conditional_mean = mean)
  })
  out <- do.call(rbind, out)
  gcpr_require(all(is.finite(c(out$relative_mass, out$conditional_mean))) &&
    all(out$relative_mass >= 0) && sum(out$relative_mass) > 0, "invalid analytic interval masses")
  out$probability <- out$relative_mass / sum(out$relative_mass)
  list(log_integral = peak + log(sum(out$relative_mass)), intervals = out,
    log_kernel = log_kernel, peak = peak,
    mean = sum(out$probability * out$conditional_mean))
}

gcpr_conditional <- function(theta, sigma, members = NULL, p = .5, member_scale = .8,
                             lag = .35, horizon = 2L) {
  c <- gcpr_contract(theta, sigma, members, p, member_scale, lag, horizon)
  M <- ncol(c$members)
  first <- if (M) sum(gcpr_log_al(c$members[1L, ], theta, p, member_scale)) else 0
  first_score <- if (M) sum(p - (c$members[1L, ] < theta)) / member_scale else 0
  if (horizon == 1L || M == 0L || lag == 0) {
    second <- if (horizon == 2L && M) sum(gcpr_log_al(c$members[2L, ], theta, p, member_scale)) else 0
    second_score <- if (horizon == 2L && M) sum(p - (c$members[2L, ] < theta)) / member_scale else 0
    return(list(log_evidence = first + second,
      mean_y1 = theta + sigma * (1 - 2 * p) / (p * (1 - p)),
      fisher_gradient = c(theta = first_score + second_score, log_sigma = 0),
      reparameterized_gradient = c(theta = first_score + second_score, log_sigma = 0),
      member_factors = horizon * M, member_weights = rep(1, horizon * M),
      integration = "normalized_future_response_factors_integrated_exactly",
      original_reads = 0L, production_qualified = FALSE))
  }
  product <- gcpr_piecewise(c(1, rep(-lag, M)), c(-theta, c$members[2L, ] - theta),
    c(sigma, rep(member_scale, M)), p)
  q <- product$intervals
  reference_score <- (p - (q$point < theta)) / sigma
  member_score <- vapply(q$point, function(y)
    sum(p - (c$members[2L, ] - theta - lag * y < 0)) / member_scale, numeric(1L))
  # The terminal Y2 transition integrates to one even though its location
  # depends on theta and Y1. Its conditional expected score is zero.
  centered <- c(theta = first_score + sum(q$probability * (reference_score + member_score)),
    log_sigma = sum(q$probability * (-1 +
      (q$conditional_mean - theta) * (p - (q$point < theta)) / sigma)))
  noncentered <- c(theta = first_score + (1 + lag) * sum(q$probability * member_score),
    log_sigma = sum(q$probability * member_score * lag * (q$conditional_mean - theta)))
  list(log_evidence = first + product$log_integral, mean_y1 = product$mean,
    fisher_gradient = centered, reparameterized_gradient = noncentered,
    intervals = q, member_factors = horizon * M, member_weights = rep(1, horizon * M),
    integration = "analytic_piecewise_exponential_Y1_integral_with_normalized_Y2_integrated_out",
    original_reads = 0L, production_qualified = FALSE)
}

gcpr_conditional_numeric <- function(theta, sigma, members, p = .5, member_scale = .8,
                                     lag = .35, horizon = 2L) {
  c <- gcpr_contract(theta, sigma, members, p, member_scale, lag, horizon)
  if (horizon == 1L || !ncol(c$members)) return(gcpr_conditional(theta, sigma, members, p, member_scale, lag, horizon)$log_evidence)
  cuts <- sort(unique(c(-Inf, theta, if (lag != 0) (c$members[2L, ] - theta) / lag, Inf)))
  log_value <- function(y) gcpr_log_al(y, theta, p, sigma) + vapply(y, function(z)
    sum(gcpr_log_al(c$members[2L, ], theta + lag * z, p, member_scale)), numeric(1L))
  peak <- max(log_value(cuts[is.finite(cuts)]))
  mass <- sum(vapply(seq_len(length(cuts) - 1L), function(i)
    stats::integrate(function(y) exp(log_value(y) - peak), cuts[i], cuts[i + 1L],
      rel.tol = 1e-10, abs.tol = 1e-12, subdivisions = 1000L)$value, numeric(1L)))
  sum(gcpr_log_al(c$members[1L, ], theta, p, member_scale)) + peak + log(mass)
}

gcpr_conditional_cdf <- function(y, theta, sigma, members = NULL, p = .5,
                                  member_scale = .8, lag = .35, horizon = 2L) {
  gcpr_require(is.numeric(y) && !anyNA(y), "numeric CDF arguments required")
  out <- gcpr_conditional(theta, sigma, members, p, member_scale, lag, horizon)
  if (is.null(out$intervals)) {
    e <- (y - theta) / sigma
    return(ifelse(e < 0, p * exp((1 - p) * pmin(e, 0)),
      1 - (1 - p) * exp(-p * pmax(e, 0))))
  }
  q <- out$intervals
  vapply(y, function(value) {
    if (!is.finite(value)) return(if (value < 0) 0 else 1)
    total <- 0
    for (i in seq_len(nrow(q))) {
      lo <- q$lower[i]; hi <- q$upper[i]; r <- q$rate[i]
      fraction <- if (value <= lo) 0 else if (value >= hi) 1 else if (!is.finite(lo))
        exp(r * (value - hi)) else if (!is.finite(hi)) -expm1(r * (value - lo)) else
        if (r > 0) exp(r * (value - hi)) * (-expm1(-r * (value - lo))) /
          (-expm1(-r * (hi - lo))) else if (r < 0)
          (-expm1(r * (value - lo))) / (-expm1(r * (hi - lo))) else (value - lo) / (hi - lo)
      total <- total + q$probability[i] * fraction
    }
    total
  }, numeric(1L))
}

gcpr_quadrature <- function(n, shape = NULL) {
  gcpr_require(length(n) == 1L && n == floor(n) && n >= 8 && n <= 96,
    "8--96 bounded quadrature nodes required")
  k <- seq_len(n - 1L)
  if (is.null(shape)) { diagonal <- rep(0, n); off <- k / sqrt(4 * k^2 - 1) }
  else {
    gcpr_require(length(shape) == 1L && is.finite(shape) && shape > 0, "positive Gamma shape required")
    diagonal <- 2 * seq_len(n) + shape - 2; off <- sqrt(k * (k + shape - 1))
  }
  J <- diag(diagonal)
  J[cbind(k, k + 1L)] <- J[cbind(k + 1L, k)] <- off
  e <- eigen(J, symmetric = TRUE)
  list(nodes = e$values, weights = e$vectors[1L, ]^2 * if (is.null(shape)) 2 else 1)
}

gcpr_parameter_integral <- function(members = NULL, p = .5, member_scale = .8, lag = .35,
    horizon = 2L, prior_mean = .1, prior_sd = .2, shape = 4, rate = .3,
    theta_nodes = 32L, scale_nodes = 48L, theta_range_sd = 8) {
  gcpr_contract(prior_mean, rate / shape, members, p, member_scale, lag, horizon)
  gcpr_require(all(is.finite(c(prior_mean, prior_sd, shape, rate, theta_range_sd))) &&
    prior_sd > 0 && shape > 2 && rate > 0 && theta_range_sd >= 8 && theta_range_sd <= 12,
    "proper finite Normal coefficient and inverse-gamma scale priors required")
  legendre <- gcpr_quadrature(theta_nodes)
  lo <- prior_mean - theta_range_sd * prior_sd; hi <- prior_mean + theta_range_sd * prior_sd
  knots <- if (is.null(members)) numeric() else c(members[1L, ],
    if (horizon == 2L && lag != -1) members[2L, ] / (1 + lag))
  cuts <- sort(unique(c(lo, knots[knots > lo & knots < hi], hi)))
  gcpr_require(3 * (length(cuts) - 1L) * theta_nodes * scale_nodes <= 100000L,
    "bounded two-dimensional parameter quadrature exceeds generated evaluation budget")
  theta <- weight_theta <- numeric()
  for (i in seq_len(length(cuts) - 1L)) {
    half <- (cuts[i + 1L] - cuts[i]) / 2; mid <- (cuts[i + 1L] + cuts[i]) / 2
    points <- mid + half * legendre$nodes
    theta <- c(theta, points)
    weight_theta <- c(weight_theta, half * legendre$weights * stats::dnorm(points, prior_mean, prior_sd))
  }
  # sigma^j IG(sigma;a,b) = b^j Gamma(a-j)/Gamma(a) IG(sigma;a-j,b).
  # Moment shifting avoids pretending that a low-order quadrature accurately
  # resolves inverse powers of precision close to zero.
  integral <- lapply(0:2, function(j) {
    gamma <- gcpr_quadrature(scale_nodes, shape - j)
    sigma <- rate / gamma$nodes
    values <- lapply(seq_along(theta), function(i) {
      log_evidence <- vapply(sigma, function(s) gcpr_conditional(theta[i], s, members,
        p, member_scale, lag, horizon)$log_evidence, numeric(1L))
      data.frame(theta = theta[i], prior_weight = weight_theta[i] * gamma$weights,
        log_evidence = log_evidence)
    })
    grid <- do.call(rbind, values); shift <- max(grid$log_evidence)
    w <- grid$prior_weight * exp(grid$log_evidence - shift); norm <- sum(w)
    gcpr_require(is.finite(norm) && norm > 0, "failed joint parameter quadrature")
    w <- w / norm; mt <- sum(w * grid$theta)
    list(log_integral = shift + log(norm) + j * log(rate) + lgamma(shape - j) - lgamma(shape),
      theta_mean = mt, theta_variance = sum(w * (grid$theta - mt)^2), evaluations = nrow(grid))
  })
  logZ <- integral[[1L]]$log_integral; mt <- integral[[1L]]$theta_mean
  ms <- exp(integral[[2L]]$log_integral - logZ)
  second <- exp(integral[[3L]]$log_integral - logZ)
  M <- if (is.null(members)) 0L else ncol(members)
  log_upper <- horizon * M * log(p * (1 - p) / member_scale)
  tail <- 2 * stats::pnorm(-theta_range_sd)
  list(log_evidence = logZ, theta_mean = mt, sigma_mean = ms,
    theta_variance = integral[[1L]]$theta_variance, sigma_variance = second - ms^2,
    theta_sigma_covariance = ms * (integral[[2L]]$theta_mean - mt),
    prior_mass_in_theta_range = sum(weight_theta), theta_range_sd = theta_range_sd,
    prior_theta_tail_probability = tail,
    outside_theta_evidence_upper_bound = exp(log_upper) * tail,
    relative_outside_theta_evidence_bound = exp(log_upper - logZ) * tail,
    evaluations = sum(vapply(integral, function(x) x$evaluations, integer(1L))),
    parameter_unknowns = c("theta", "future_AL_scale"),
    parameter_priors = "independent proper Normal(theta) and IG(future_AL_scale)",
    fixed_parameters = "member scale, autoregressive coefficients, no RHS in this integration",
    integration = "bounded tensor Gauss-Legendre/Gamma moment-shift quadrature; require node and range comparisons",
    original_reads = 0L, production_qualified = FALSE)
}

gcpr_log_bound_one_particle <- function(theta, sigma, members, p = .5,
                                        member_scale = .8, lag = .35) {
  c <- gcpr_contract(theta, sigma, members, p, member_scale, lag, 2L)
  exact <- gcpr_conditional(theta, sigma, members, p, member_scale, lag, 2L)
  if (!ncol(c$members)) return(list(expected_log_estimate = 0, exact_log_evidence = 0, Jensen_gap = 0))
  cuts <- sort(unique(c(-Inf, theta, if (lag != 0) (members[2L, ] - theta) / lag, Inf)))
  first <- sum(gcpr_log_al(members[1L, ], theta, p, member_scale))
  expectation <- sum(vapply(seq_len(length(cuts) - 1L), function(i)
    stats::integrate(function(y) exp(gcpr_log_al(y, theta, p, sigma)) * vapply(y, function(z)
      sum(gcpr_log_al(members[2L, ], theta + lag * z, p, member_scale)), numeric(1L)),
      cuts[i], cuts[i + 1L], rel.tol = 1e-10, abs.tol = 1e-11,
      subdivisions = 1000L)$value, numeric(1L)))
  list(expected_log_estimate = first + expectation, exact_log_evidence = exact$log_evidence,
    Jensen_gap = exact$log_evidence - first - expectation,
    interpretation = "E(log unbiased one-particle normalizer) is not log exact normalizer")
}

gcpr_log_ig <- function(x, shape, rate) shape * log(rate) - lgamma(shape) - (shape + 1) * log(x) - rate / x

gcpr_one_horizon_joint_scale <- function(members = numeric(), p = .5,
    prior_mean = .1, prior_sd = .2, shape = 4, rate = .3) {
  gcpr_require(is.numeric(members) && length(members) %in% c(0L, 1L, 51L) &&
    all(is.finite(c(members, prior_mean, prior_sd, shape, rate, p))) &&
    prior_sd > 0 && shape > 2 && rate > 0 && p > 0 && p < 1,
    "proper joint coefficient/shared-scale one-horizon target required")
  M <- length(members); posterior_shape <- shape + M
  posterior_rate <- function(theta) rate + vapply(theta, function(t)
    sum(gcpr_rho(members - t, p)), numeric(1L))
  log_constant <- shape * log(rate) + lgamma(posterior_shape) - lgamma(shape) +
    M * log(p * (1 - p))
  log_kernel <- function(theta) stats::dnorm(theta, prior_mean, prior_sd, log = TRUE) +
    log_constant - posterior_shape * log(posterior_rate(theta))
  knots <- sort(unique(members))
  bracket <- range(c(prior_mean + c(-8, 8) * prior_sd, members))
  mode <- stats::optimize(log_kernel, bracket, maximum = TRUE, tol = 1e-12)$maximum
  peak <- max(log_kernel(c(mode, knots, prior_mean)))
  integrate <- function(fun, extra = numeric()) {
    points <- sort(unique(c(-Inf, knots, prior_mean, mode, extra, Inf)))
    sum(vapply(seq_len(length(points) - 1L), function(i) stats::integrate(fun,
      points[i], points[i + 1L], rel.tol = 1e-10, abs.tol = 1e-12,
      subdivisions = 1000L)$value, numeric(1L)))
  }
  kernel <- function(theta) exp(log_kernel(theta) - peak)
  norm <- integrate(kernel)
  density <- function(theta) kernel(theta) / norm
  mt <- integrate(function(t) t * density(t))
  vt <- integrate(function(t) (t - mt)^2 * density(t))
  ms <- integrate(function(t) posterior_rate(t) / (posterior_shape - 1) * density(t))
  second <- integrate(function(t) posterior_rate(t)^2 /
    ((posterior_shape - 1) * (posterior_shape - 2)) * density(t))
  cross <- integrate(function(t) (t - mt) * posterior_rate(t) /
    (posterior_shape - 1) * density(t))
  future_cdf <- function(y) vapply(y, function(value) {
    if (!is.finite(value)) return(if (value < 0) 0 else 1)
    integrate(function(t) {
      b <- posterior_rate(t); e <- value - t
      cdf <- ifelse(e < 0, p * (b / (b + (1 - p) * pmax(-e, 0)))^posterior_shape,
        1 - (1 - p) * (b / (b + p * pmax(e, 0)))^posterior_shape)
      density(t) * cdf
    }, extra = value)
  }, numeric(1L))
  list(log_evidence = peak + log(norm), theta_mean = mt, theta_variance = vt,
    sigma_mean = ms, sigma_variance = second - ms^2, theta_sigma_covariance = cross,
    conditional_sigma_shape = posterior_shape, conditional_sigma_rate = posterior_rate,
    future_cdf = future_cdf, parameter_density = density,
    normalization = integrate(density), member_weights = rep(1, M),
    unknown_parameters = c("theta", "shared_AL_scale"),
    integration = "exact inverse-gamma scale integral followed by split one-dimensional coefficient quadrature",
    original_reads = 0L, production_qualified = FALSE,
    scope = "controlled shared-scale Normal-prior target, not production source-specific scales or NS hierarchy")
}

gcpr_ns_log_joint <- function(beta, tau2, lambda2, zeta2, xi, nu, tau0 = .1,
                              slab_shape = 2, slab_rate = 4) {
  r <- length(beta)
  gcpr_require(r > 0L && length(lambda2) == r && length(nu) == r &&
    all(is.finite(c(beta, tau2, lambda2, zeta2, xi, nu, tau0, slab_shape, slab_rate))) &&
    all(c(tau2, lambda2, zeta2, xi, nu, tau0, slab_shape, slab_rate) > 0), "positive complete NS hierarchy required")
  sum(stats::dnorm(beta, 0, sqrt(tau2 * lambda2), log = TRUE)) +
    sum(stats::dnorm(beta, 0, sqrt(zeta2), log = TRUE)) +
    gcpr_log_ig(tau2, .5, 1 / xi) + gcpr_log_ig(xi, .5, 1 / tau0^2) +
    sum(gcpr_log_ig(lambda2, .5, 1 / nu)) + sum(gcpr_log_ig(nu, .5, 1)) +
    gcpr_log_ig(zeta2, slab_shape, slab_rate)
}
