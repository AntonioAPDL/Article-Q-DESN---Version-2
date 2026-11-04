# Generated-only complete-parameter oracle; no evidence read or application fit.
local({
  source("scripts/diagnostics/glofas_coupled_parameter_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  for (p in c(.05, .2, .5, .8, .95)) {
    empty <- gcp_one_step_reference(prior_mean = .1, prior_sd = .3, probability = p)
    ok(abs(empty$parameter_mean - .1) < 1e-8)
    ok(abs(empty$parameter_variance - .09) < 1e-8)
    ok(abs(empty$log_member_evidence) < 1e-8)
    ok(abs(empty$parameter_normalization - 1) < 1e-9)
    ok(abs(empty$coefficient_response_covariance - .09) < 1e-8)
    ok(min(eigen(empty$joint_covariance, symmetric = TRUE)$values) > 0)
    # Independent closed Normal--AL convolution checks the quadrature CDF.
    y <- c(-1, 0, 1); z <- (y - .1) / .3
    a <- (1 - p) / .07; b <- p / .07
    analytic <- stats::pnorm(z) - (1 - p) * exp(-b * (y - .1) + .5 * b^2 * .3^2) *
      stats::pnorm(z - b * .3) + p * exp(a * (y - .1) + .5 * a^2 * .3^2) *
      stats::pnorm(-z - a * .3)
    ok(max(abs(empty$future_cdf(y) - analytic)) < 1e-8)
    ok(identical(empty$future_cdf(c(-Inf, Inf)), c(0, 1)))
    for (members in list(.2, rep(.2, 51L))) {
      ref <- gcp_one_step_reference(prior_mean = .1, prior_sd = .3,
        probability = p, members = members)
      ok(abs(ref$parameter_normalization - 1) < 1e-9)
      ok(ref$member_count == length(members) && all(ref$member_weights == 1))
      ok(ref$parameter_variance < .09)
      ok(abs(ref$coefficient_response_covariance - ref$parameter_variance) < 1e-14)
      ok(min(eigen(ref$joint_covariance, symmetric = TRUE)$values) > 0)
      probs <- c(.1, p, .9)
      quantiles <- ref$future_quantile(probs)
      ok(max(abs(ref$future_cdf(quantiles) - probs)) < 1e-7)
      ok(all(is.finite(quantiles)) && identical(ref$production_qualified, FALSE))
      # Independent integration of the complete joint density at a fixed
      # coefficient: every AL transition is normalized, even with asymmetry.
      t <- ref$parameter_mean
      integral <- stats::integrate(function(y) exp(gcp_al_log_density(y, t, p, .07)),
        -Inf, t, rel.tol = 1e-10)$value +
        stats::integrate(function(y) exp(gcp_al_log_density(y, t, p, .07)),
          t, Inf, rel.tol = 1e-10)$value
      ok(abs(integral - 1) < 1e-9)
    }
  }
  # Same posterior after a simultaneous translation of prior and observations.
  a <- gcp_one_step_reference(prior_mean = 0, members = c(-.1, .1), probability = .5)
  b <- gcp_one_step_reference(prior_mean = 3, members = 3 + c(-.1, .1), probability = .5)
  ok(abs(a$parameter_mean + 3 - b$parameter_mean) < 1e-8)
  ok(abs(a$parameter_variance - b$parameter_variance) < 1e-8)
  ok(abs(a$future_quantile(.5) + 3 - b$future_quantile(.5)) < 1e-7)
  ok(inherits(try(gcp_one_step_reference(prior_sd = 0), silent = TRUE), "try-error"))
  ok(inherits(try(gcp_one_step_reference(members = rep(0, 52)), silent = TRUE), "try-error"))
  narrow <- gcp_one_step_reference(prior_mean = .1, probability = .05, members = rep(.2, 51))
  tail_cdf <- narrow$future_cdf(c(-1.5188429090677675, -.5, .2))
  ok(all(is.finite(tail_cdf)) && all(diff(tail_cdf) > 0) && tail_cdf[1L] > 0)
  cat(sprintf("GLOFAS_COUPLED_PARAMETER_REFERENCE_PASS checks=%d original_reads=0 fits=0 production_qualified=FALSE\n", checks))
})
