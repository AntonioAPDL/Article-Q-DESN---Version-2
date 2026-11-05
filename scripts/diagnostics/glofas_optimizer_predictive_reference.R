# Controlled shared-scale H1 predictive functionals, not native GloFAS fits.
# Exact posterior references integrate IG scale analytically; Gaussian-q
# predictions condition theta on log(sigma) and use one-dimensional GH only.
# No payload access, random draws, physical clipping or result promotion.

gopr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS optimizer predictive reference: ", why), call. = FALSE)
  invisible(TRUE)
}
gopr_log_mills_positive <- function(x) {
  gopr_require(is.numeric(x) && !anyNA(x) && all(x >= 8), "positive tail Mills arguments required")
  # Laplace's convergent continued fraction, not log-Phi + x^2/2 subtraction.
  denominator <- numeric(length(x))
  for (j in 40:1) denominator <- j / (x + denominator)
  -log(x + denominator)
}
gopr_log_product <- function(z, log_a, linear_exponent) {
  a <- exp(log_a); x <- z + a
  out <- numeric(length(z)); indeterminate <- is.nan(x)
  out[indeterminate] <- -Inf # a=Inf, z=-Inf: both response-scale tails are negligible.
  tail <- !indeterminate & x >= 8
  if (any(tail)) {
    log_mills <- gopr_log_mills_positive(x[tail])
    # When a overflows, its logarithm is still finite and dominates finite z.
    huge <- is.infinite(a) & tail
    if (any(huge)) log_mills[is.infinite(x[tail])] <- -log_a
    out[tail] <- -.5 * z[tail]^2 - .5 * log(2 * pi) + log_mills
  }
  remaining <- !tail & !indeterminate
  if (any(remaining)) {
    at <- z[remaining]
    exponent <- if (a == 0) linear_exponent[remaining] else a * (at + .5 * a)
    overflow_z <- is.infinite(at)
    if (any(overflow_z)) {
      replacement <- linear_exponent[remaining][overflow_z]
      finite_linear <- is.finite(replacement)
      replacement[finite_linear] <- replacement[finite_linear] + .5 * a^2
      exponent[overflow_z] <- replacement
    }
    out[remaining] <- exponent + stats::pnorm(-x[remaining], log.p = TRUE)
  }
  out
}
gopr_normal_al_cdf <- function(y, location_mean, location_sd, scale, probability = .2) {
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  gopr_require(is.numeric(y) && !anyNA(y) && all(vapply(list(location_mean, location_sd,
    scale, probability), scalar, logical(1L))) && location_sd >= 0 && scale > 0 &&
    probability > 0 && probability < 1, "numeric CDF arguments, nonnegative Normal SD and positive AL scale required")
  out <- numeric(length(y)); out[y == Inf] <- 1
  keep <- is.finite(y)
  if (!any(keep)) return(out)
  residual <- y[keep] - location_mean; p <- probability
  if (location_sd == 0) {
    standardized <- residual / scale; left <- standardized < 0
    value <- numeric(length(residual))
    value[left] <- p * exp((1 - p) * standardized[left])
    value[!left] <- 1 - (1 - p) * exp(-p * standardized[!left])
  } else {
    z <- residual / location_sd
    log_ratio <- log(location_sd) - log(scale)
    positive <- gopr_log_product(z, log1p(-p) + log_ratio, (1 - p) * residual / scale)
    negative <- gopr_log_product(-z, log(p) + log_ratio, -p * residual / scale)
    value <- stats::pnorm(z) + p * exp(positive) - (1 - p) * exp(negative)
  }
  gopr_require(all(is.finite(value)) && all(value >= -128 * .Machine$double.eps &
    value <= 1 + 128 * .Machine$double.eps), "nonrepresentable or inaccurate convolution CDF")
  # Roundoff of a probability only; no scale, draw or model parameter is clipped.
  out[keep] <- pmin(1, pmax(0, value))
  out
}
gopr_gaussian_predictive_cdf <- function(y, mean, log_sd, factor = diag(2L),
    nodes = 32L, probability = .2) {
  gopr_require(exists("gcpor_gaussian_contract", mode = "function") &&
    exists("gcpor_normal_quadrature", mode = "function"), "load generated Gaussian references first")
  q <- gcpor_gaussian_contract(mean, log_sd, factor)
  gopr_require(q$p == 2L && nodes %in% c(32L, 64L), "two uncertain coordinates and 32/64 GH nodes required")
  V <- q$covariance; s_eta <- sqrt(V[2L, 2L])
  conditional_variance <- V[1L, 1L] - V[1L, 2L]^2 / V[2L, 2L]
  gopr_require(is.finite(conditional_variance) && conditional_variance > 0,
    "positive conditional theta variance required; no silent diagonalization")
  rule <- gcpor_normal_quadrature(nodes)
  eta <- mean[2L] + s_eta * rule$nodes
  conditional_mean <- mean[1L] + V[1L, 2L] / s_eta * rule$nodes
  sigma <- exp(eta)
  gopr_require(all(is.finite(sigma)) && all(sigma > 0), "GH scales are not representable; no clipping permitted")
  out <- numeric(length(y))
  for (j in seq_along(eta)) out <- out + rule$weights[j] * gopr_normal_al_cdf(y,
    conditional_mean[j], sqrt(conditional_variance), sigma[j], probability)
  gopr_require(all(is.finite(out)) && all(out >= -128 * .Machine$double.eps &
    out <= 1 + 128 * .Machine$double.eps), "invalid integrated predictive CDF")
  pmin(1, pmax(0, out))
}
gopr_quantile <- function(cdf, probability, center, width, tolerance = 1e-10, max_expansions = 40L) {
  gopr_require(is.function(cdf) && is.numeric(probability) && length(probability) == 1L &&
    is.finite(probability) && probability > 0 && probability < 1 &&
    is.numeric(center) && length(center) == 1L && is.finite(center) &&
    is.numeric(width) && length(width) == 1L && is.finite(width) && width > 0 &&
    is.numeric(tolerance) && length(tolerance) == 1L && is.finite(tolerance) && tolerance > 0 &&
    max_expansions %in% 1:40, "finite explicit quantile bracket and interior probability required")
  evaluate <- function(x) {
    value <- cdf(x)
    gopr_require(is.numeric(value) && length(value) == 1L && is.finite(value) && value >= 0 && value <= 1,
      "CDF must return one valid probability")
    value - probability
  }
  for (i in 0:max_expansions) {
    lo <- center - width; hi <- center + width
    gopr_require(all(is.finite(c(lo, hi))), "quantile bracket overflow; no artificial endpoint")
    lower <- evaluate(lo); upper <- evaluate(hi)
    if (lower <= 0 && upper >= 0) return(stats::uniroot(evaluate, c(lo, hi),
      f.lower = lower, f.upper = upper, tol = tolerance)$root)
    width <- 2 * width
  }
  stop("GloFAS optimizer predictive reference: finite quantile bracket budget exhausted", call. = FALSE)
}
gopr_assess_h1 <- function(members = numeric(), probability = .2, fit = NULL,
    prior_mean = .1, prior_sd = .2, shape = 4, rate = .3) {
  # These gates are fixed before fixture evaluation; no exposed override.
  gates <- list(primary_quantile_absolute_error = .001, maximum_grid_CDF_error = .01,
    GH_CDF_difference = 1e-8, GH_quantile_difference = 1e-7)
  levels <- c(.05, .2, .5, .8, .95)
  gopr_require(identical(probability, .2), "this prespecified controlled benchmark uses model p=0.2")
  truth <- gcpor_h1_joint_moments(members, probability, prior_mean, prior_sd, shape, rate)
  if (is.null(fit)) fit <- gcpor_h1_optimize(c(prior_mean, log(rate / shape) + 1 / (2 * shape)),
    c(log(prior_sd), -.5 * log(shape)), members = members, probability = probability,
    prior_mean = prior_mean, prior_sd = prior_sd, shape = shape, rate = rate)
  gopr_require(is.list(fit), "supplied Gaussian fit must retain its parameter coordinates")
  factor <- fit$factor
  if (is.null(factor) && !is.null(fit$covariance)) {
    covariance <- fit$covariance
    gopr_require(is.matrix(covariance) && is.numeric(covariance) && identical(dim(covariance), c(2L,2L)) &&
      all(is.finite(covariance)) && max(abs(covariance-t(covariance))) < 1e-12,
      "retained Gaussian covariance must be finite and symmetric")
    ch <- tryCatch(chol(covariance), error = function(e) NULL)
    gopr_require(!is.null(ch), "retained Gaussian covariance must be positive definite")
    # The independent reference retains covariance, not its input factor.
    factor <- sweep(t(ch), 2L, exp(fit$log_sd), "/")
  }
  if (is.null(factor)) factor <- diag(2L)
  q <- gcpor_gaussian_contract(fit$mean, fit$log_sd, factor)
  if (!is.null(fit$covariance)) gopr_require(max(abs(q$covariance-fit$covariance)) <=
    1e-10 * max(1,max(abs(fit$covariance))), "factor and retained covariance disagree")
  exact_q_ELBO <- gcpor_h1_elbo(fit$mean,fit$log_sd,factor,members,probability,
    prior_mean,prior_sd,shape,rate)$value
  supplied_ELBO <- if (is.numeric(fit$value) && length(fit$value)==1L && is.finite(fit$value)) fit$value else NA_real_
  moments <- gcpor_gaussian_physical_moments(fit$mean, fit$log_sd, factor)
  width <- max(prior_sd, moments$sigma_mean / min(probability, 1 - probability),
    truth$sigma_mean / min(probability, 1 - probability))
  exact_cdf <- truth$future_cdf
  f32 <- function(y) gopr_gaussian_predictive_cdf(y, fit$mean, fit$log_sd, factor, 32L, probability)
  f64 <- function(y) gopr_gaussian_predictive_cdf(y, fit$mean, fit$log_sd, factor, 64L, probability)
  exact_quantiles <- vapply(levels, function(p) gopr_quantile(exact_cdf, p, truth$mean[1L], width), numeric(1L))
  q32 <- vapply(levels, function(p) gopr_quantile(f32, p, fit$mean[1L], width), numeric(1L))
  q64 <- vapply(levels, function(p) gopr_quantile(f64, p, fit$mean[1L], width), numeric(1L))
  # A declared finite assessment grid, not an asserted supremum over all y.
  knots <- sort(unique(c(exact_quantiles, q64)))
  grid <- sort(unique(c(knots, (knots[-1L] + knots[-length(knots)]) / 2)))
  exact <- exact_cdf(grid); approx32 <- f32(grid); approx64 <- f64(grid)
  error <- abs(q64 - exact_quantiles); primary <- which(levels == probability)
  CDF_error <- max(abs(approx64 - exact))
  node_CDF <- max(abs(approx64 - approx32)); node_quantile <- max(abs(q64 - q32))
  quadrature_pass <- node_CDF <= gates$GH_CDF_difference && node_quantile <= gates$GH_quantile_difference
  pass <- error[primary] <= gates$primary_quantile_absolute_error &&
    CDF_error <= gates$maximum_grid_CDF_error && quadrature_pass
  list(schema_version = "glofas_generated_H1_predictive_reference_v1", gates = gates,
    status = if (pass) "CONTROLLED_PREDICTIVE_GATES_PASS_NOT_NATIVE_QUALIFICATION" else
      "CONTROLLED_PREDICTIVE_GATE_REVIEW_RETAIN_ALL_RESULTS",
    predictive_gates_passed = pass, quadrature_comparison_passed = quadrature_pass,
    model_probability = probability, member_count = length(members),
    quantiles = data.frame(probability = levels, exact = exact_quantiles, Gaussian_q_32 = q32,
      Gaussian_q_64 = q64, absolute_error = error),
    CDF = data.frame(y = grid, exact = exact, Gaussian_q_32 = approx32, Gaussian_q_64 = approx64),
    primary_quantile_absolute_error = unname(error[primary]), maximum_grid_CDF_error = CDF_error,
    GH_maximum_CDF_difference = node_CDF, GH_maximum_quantile_difference = node_quantile,
    parameter_mean = data.frame(coordinate = c("theta", "log_sigma"),
      exact = unname(truth$mean), Gaussian_q = fit$mean),
    parameter_variance = data.frame(coordinate = c("theta", "log_sigma"), exact = diag(truth$covariance),
      Gaussian_q = diag(q$covariance), ratio = diag(q$covariance) / diag(truth$covariance)),
    theta_log_sigma_covariance_exact = truth$covariance[1L, 2L],
    theta_log_sigma_covariance_q = q$covariance[1L, 2L],
    theta_sigma_covariance_exact = truth$theta_sigma_covariance,
    theta_sigma_covariance_q = moments$theta_sigma_covariance,
    exact_log_evidence = truth$log_evidence, Gaussian_family_ELBO = exact_q_ELBO,
    supplied_fit_ELBO = supplied_ELBO, supplied_fit_ELBO_discrepancy = supplied_ELBO-exact_q_ELBO,
    reference_family_KL = truth$log_evidence - exact_q_ELBO,
    assessment_scope = "Controlled H1 uncertain coefficient/shared AL scale, not native source-specific Y/G scales or RHS; CDF error is on the declared quantile/midpoint grid.",
    full_posterior_accuracy_qualified = FALSE, production_qualified = FALSE,
    native_launch_authorized = FALSE, publication_authorized = FALSE,
    original_reads = 0L, application_fits = 0L)
}
