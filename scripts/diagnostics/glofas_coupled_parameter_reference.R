# Generated one-step complete-parameter references, not application inference.
# No file reads, likelihood callbacks, fits, tuning, or publication operations.
gcp_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS coupled reference: ", why), call. = FALSE)
  invisible(TRUE)
}
gcp_al_cdf <- function(y, location, probability, scale) {
  e <- y - location
  ifelse(e < 0, probability * exp((1 - probability) * pmin(e, 0) / scale),
    1 - (1 - probability) * exp(-probability * pmax(e, 0) / scale))
}
gcp_al_log_density <- function(y, location, probability, scale) {
  e <- y - location
  log(probability * (1 - probability) / scale) - e * (probability - (e < 0)) / scale
}
gcp_one_step_reference <- function(prior_mean = 0, prior_sd = .3,
    probability = .5, response_scale = .07, member_scale = .05,
    members = numeric(), discrepancy = 0, relative_tolerance = 1e-9) {
  q <- gcp_require
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  q(all(vapply(list(prior_mean, prior_sd, probability, response_scale,
    member_scale, discrepancy, relative_tolerance), scalar, logical(1L))) &&
    prior_sd > 0 && response_scale > 0 && member_scale > 0 && probability > 0 &&
    probability < 1 && relative_tolerance > 0 && relative_tolerance <= 1e-7,
    "finite probability/scale/proper Normal prior required")
  q(is.numeric(members) && length(members) <= 51L && all(is.finite(members)),
    "zero to fifty-one ordinary generated member factors required")
  knots <- sort(unique(members - discrepancy))
  log_theta <- function(theta) vapply(theta, function(t) stats::dnorm(t, prior_mean,
    prior_sd, log = TRUE) + sum(gcp_al_log_density(members, t + discrepancy,
      probability, member_scale)), numeric(1L))
  bracket <- range(c(prior_mean - 8 * prior_sd, prior_mean + 8 * prior_sd, knots))
  optimum <- stats::optimize(log_theta, bracket, maximum = TRUE, tol = 1e-12)
  centre <- max(log_theta(c(optimum$maximum, prior_mean, knots)))
  boundaries <- c(-Inf, sort(unique(c(prior_mean, knots))), Inf)
  integrate_segments <- function(fun, extra = numeric()) {
    split <- sort(unique(c(boundaries, extra)))
    sum(vapply(seq_len(length(split) - 1L), function(j)
      stats::integrate(fun, split[j], split[j + 1L],
        rel.tol = relative_tolerance, abs.tol = 1e-13, subdivisions = 1000L,
        stop.on.error = TRUE)$value, numeric(1L)))
  }
  unnormalized <- function(theta) exp(log_theta(theta) - centre)
  normalizer <- integrate_segments(unnormalized)
  q(is.finite(normalizer) && normalizer > 0, "failed parameter normalization")
  density <- function(theta) unnormalized(theta) / normalizer
  mean_theta <- integrate_segments(function(t) t * density(t))
  variance_theta <- integrate_segments(function(t) (t - mean_theta)^2 * density(t))
  q(is.finite(mean_theta) && is.finite(variance_theta) && variance_theta > 0,
    "failed complete-parameter moments")
  future_cdf <- function(y) {
    q(is.numeric(y) && all(!is.na(y)), "numeric CDF arguments required")
    vapply(y, function(value) {
      if (!is.finite(value)) return(if (value < 0) 0 else 1)
      # Rescale the positive CDF-weighted integrand independently. Integrating
      # a tiny unscaled tail can make QUADPACK miss a narrow member-conditioned
      # coefficient density, even when its requested absolute error is small.
      log_cdf <- function(t) {
        e <- value - t
        ifelse(e < 0, log(probability) + (1 - probability) * pmin(e, 0) / response_scale,
          log1p(-(1 - probability) * exp(-probability * pmax(e, 0) / response_scale)))
      }
      weighted_log <- function(t) log_theta(t) + log_cdf(t)
      weighted_bracket <- range(c(bracket, value,
        prior_mean - prior_sd^2 * (1 - probability) / response_scale))
      weighted_optimum <- stats::optimize(weighted_log, weighted_bracket,
        maximum = TRUE, tol = 1e-12)
      weighted_centre <- max(weighted_log(c(weighted_optimum$maximum, knots,
        prior_mean, value)))
      integral <- integrate_segments(function(t) exp(weighted_log(t) - weighted_centre),
        extra = c(value, weighted_optimum$maximum))
      result <- exp(weighted_centre - centre) * integral / normalizer
      q(is.finite(result) && result >= -1e-9 && result <= 1 + 1e-9,
        "CDF quadrature did not produce a probability")
      min(1, max(0, result)) # only probability roundoff, never response clipping
    }, numeric(1L))
  }
  future_quantile <- function(probs) {
    q(is.numeric(probs) && all(is.finite(probs)) && all(probs > 0 & probs < 1),
      "interior quantile probabilities required")
    initial_width <- prior_sd + response_scale / min(probability, 1 - probability)
    vapply(probs, function(p) {
      width <- initial_width
      for (i in seq_len(30L)) {
        interval <- mean_theta + c(-1, 1) * width
        if (future_cdf(interval[1L]) < p && future_cdf(interval[2L]) > p) break
        width <- 2 * width
      }
      stats::uniroot(function(y) future_cdf(y) - p, interval,
        tol = 1e-9, maxiter = 200L)$root
    }, numeric(1L))
  }
  A <- (1 - 2 * probability) / (probability * (1 - probability))
  noise_variance <- response_scale^2 * (1 - 2 * probability + 2 * probability^2) /
    (probability^2 * (1 - probability)^2)
  joint_covariance <- matrix(c(variance_theta, variance_theta, variance_theta,
    variance_theta + noise_variance), 2L, 2L,
    dimnames = list(c("coefficient", "future_response"), c("coefficient", "future_response")))
  list(schema_version = "glofas_generated_coupled_one_step_reference_v1",
    scope = "generated_proper_Normal_coefficient_prior_fixed_scales_one_step_only",
    probability = probability, member_count = length(members), member_weights = rep(1, length(members)),
    prior_mean = prior_mean, prior_variance = prior_sd^2,
    parameter_mean = mean_theta, parameter_variance = variance_theta,
    future_mean = mean_theta + response_scale * A,
    future_variance = variance_theta + noise_variance,
    coefficient_response_covariance = variance_theta, joint_covariance = joint_covariance,
    parameter_density = density, future_cdf = future_cdf, future_quantile = future_quantile,
    log_member_evidence = centre + log(normalizer),
    parameter_normalization = integrate_segments(density),
    original_reads = 0L, application_fits = 0L, production_qualified = FALSE,
    note = "Future response conditional density integrates to one. Issued members legitimately update coefficients; the unobserved response alone cannot. This does not qualify RHS, exAL or nonlinear application inference.")
}
