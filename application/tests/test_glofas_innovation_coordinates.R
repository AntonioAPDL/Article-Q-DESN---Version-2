# Generated mathematical tests only: no authentic payloads, fits or sampling.
local({
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_coupled_parameter_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  close <- function(x, y, tol = 1e-9) ok(max(abs(x - y)) < tol)
  fails <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  constant <- function(h, past, theta) theta[1L]
  affine <- function(h, past, theta) theta[1L] + if (h > 1L) .4 * tail(past, 1L) else 0
  nonlinear <- function(h, past, theta) theta[1L] + if (h > 1L)
    .3 * tanh(tail(past, 1L)) + .05 * tail(past, 1L)^2 else 0
  unknown_scale <- function(h, past, theta) exp(theta[2L]) *
    (1 + if (h > 1L) .05 * abs(tail(past, 1L)) else 0)
  jacobian <- function(fun, point, step = 1e-6) {
    vapply(seq_along(point), function(j) {
      d <- rep(0, length(point)); d[j] <- step
      (fun(point + d) - fun(point - d)) / (2 * step)
    }, numeric(length(fun(point))))
  }
  integral <- function(fun, a, b) stats::integrate(fun, a, b,
    rel.tol = 1e-9, abs.tol = 1e-11, subdivisions = 500L)$value

  # Scalar AL identities, including far tails that round pnorm(z) to 0 or 1.
  for (p in c(.05, .2, .5, .8, .95)) {
    u <- c(1e-12, .001, .1, p, .8, 1 - 1e-12)
    y <- gic_al_quantile(u, p, .2, .3)
    close(gic_al_cdf(y, .2, p, .3), u, 1e-13)
    close(gic_al_log_density(y, .2, p, .3), gcp_al_log_density(y, .2, p, .3), 1e-12)
    close(gic_al_cdf(c(-Inf, Inf), probability = p), c(0, 1))
    close(gic_al_cdf(c(-Inf, Inf), probability = p, lower.tail = FALSE), c(1, 0))
    close(gic_al_cdf(.2, .2, p, .3), p)
    norm <- integral(function(x) exp(gic_al_log_density(x, .2, p, .3)), -Inf, .2) +
      integral(function(x) exp(gic_al_log_density(x, .2, p, .3)), .2, Inf)
    close(norm, 1)
    for (z in c(-30, -8, -.4, 0, .7, 8, 30)) {
      f <- gic_al_forward(z, .2, constant, .3, p)
      inverse <- gic_al_inverse(f$path, .2, constant, .3, p)
      close(inverse$base, z, 2e-9)
      close(f$log_path_density + f$log_abs_jacobian, f$log_base_density, 1e-10)
      ok(is.finite(f$log_abs_jacobian) && !f$production_qualified)
    }
    z <- c(-37, -30, -8, 0, 8, 30, 37)
    e <- gic_al_standardized_from_normal(z, p)
    close(gic_al_normal_from_standardized(e, p), z, 1e-8)
  }
  # log(1-exp(x)) must not subtract probabilities rounded to one.
  close(gic_log1mexp(-1e-100), log(1e-100), 1e-12)
  close(gic_al_cdf(1, probability = 1e-100) / 1e-100, 2, 1e-12)
  close(gic_al_cdf(0, probability = 1e-100) / 1e-100, 1, 1e-12)

  # Affine and nonlinear two-horizon maps: triangular numerical derivatives,
  # forward/inverse agreement, unknown scale and exact change of density.
  theta <- c(.2, log(.35))
  for (mu in list(constant, affine, nonlinear)) {
    for (measure in c("uniform", "normal")) {
      point <- if (measure == "uniform") c(.33, .81) else c(-.4, .7)
      f <- gic_al_forward(point, theta, mu, unknown_scale, .2, measure)
      back <- gic_al_inverse(f$path, theta, mu, unknown_scale, .2, measure)
      close(back$base, point)
      close(back$path, f$path)
      close(f$identity_residual, 0, 1e-12)
      J <- jacobian(function(b) gic_al_forward(b, theta, mu, unknown_scale, .2, measure)$path, point)
      close(J[1L, 2L], 0, 1e-12)
      close(as.numeric(determinant(J, logarithm = TRUE)$modulus), f$log_abs_jacobian, 1e-6)
      ok(all(diag(J) > 0))
    }
  }
  # Include unknown intercept and log scale in the transformation. Their
  # identity output block makes the full determinant equal the path block.
  joint_point <- c(.2, log(.35), -.4, .7)
  joint_map <- function(w) c(w[1:2], gic_al_forward(w[3:4], w[1:2], nonlinear,
    unknown_scale, .2, "normal")$path)
  J <- jacobian(joint_map, joint_point)
  close(J[1:2, 1:2], diag(2L), 1e-9)
  close(J[1:2, 3:4], matrix(0, 2L, 2L), 1e-12)
  f <- gic_al_forward(joint_point[3:4], joint_point[1:2], nonlinear, unknown_scale, .2)
  close(as.numeric(determinant(J, logarithm = TRUE)$modulus), f$log_abs_jacobian, 1e-6)

  # Direct response-space normalization for a nonlinear two-horizon law.
  # Integrate at the kink at each causal location, rather than smoothing it.
  response_integral <- function(y1) {
    vapply(y1, function(a) {
      m2 <- nonlinear(2L, a, theta)
      s2 <- unknown_scale(2L, a, theta)
      second <- integral(function(y2) exp(gic_al_log_density(y2, m2, .2, s2)), -Inf, m2) +
        integral(function(y2) exp(gic_al_log_density(y2, m2, .2, s2)), m2, Inf)
      exp(gic_al_log_density(a, theta[1L], .2, exp(theta[2L]))) * second
    }, numeric(1L))
  }
  close(integral(response_integral, -Inf, theta[1L]) +
    integral(response_integral, theta[1L], Inf), 1, 1e-8)

  # All 51 ordinary factors, not a powered joint density or member average.
  members <- rbind(seq(-.1, .2, length.out = 51L), seq(.1, .5, length.out = 51L))
  member_location <- function(h, path, theta) .1 + .6 * path[h] + theta[1L]
  historical <- function(t) sum(stats::dnorm(t, log = TRUE))
  target <- gic_al_member_target(c(-.4, .7), theta, nonlinear, unknown_scale, .2,
    members, member_location, .4, historical)
  manual <- sum(vapply(1:2, function(h) sum(gic_al_log_density(members[h, ],
    member_location(h, target$transformed$path, theta), .2, .4)), numeric(1L)))
  close(target$log_member_likelihood, manual)
  close(target$log_target, historical(theta) + manual + sum(stats::dnorm(c(-.4, .7), log = TRUE)))
  close(target$log_target, historical(theta) + manual + target$transformed$log_path_density +
    target$transformed$log_abs_jacobian)
  ok(target$member_factor_count == 102L && target$member_count == 51L)
  ok(all(target$member_weights == 1) && !target$production_qualified)
  ok(abs(manual - manual / 51) > 1)

  # No members: integrating future coordinates leaves the historical parameter
  # density unchanged, even with unknown scale and nonlinear recurrence.
  for (t in list(c(-.3, log(.2)), c(.1, log(.5)), c(.8, log(1.1)))) {
    for (point in list(c(-1.2, .7), c(.2, -.6))) {
      empty <- gic_al_member_target(point, t, nonlinear, unknown_scale, .2,
        NULL, NULL, NULL, historical)
      close(empty$log_target - empty$log_historical, sum(stats::dnorm(point, log = TRUE)))
      ok(empty$member_factor_count == 0L)
    }
    # Numerical product-space normalization, with actual transformation calls.
    inner <- function(z1) vapply(z1, function(a) integral(function(z2)
      vapply(z2, function(b) exp(gic_al_member_target(c(a, b), t, nonlinear,
        unknown_scale, .2, NULL, NULL, NULL, historical)$log_target - historical(t)),
        numeric(1L)), -7, 7), numeric(1L))
    close(integral(inner, -7, 7), (stats::pnorm(7) - stats::pnorm(-7))^2, 1e-8)
  }

  # Existing exact complete-parameter reference, with a proper coefficient
  # distribution and 51 members. Future response integration does not turn
  # historical parameter uncertainty into a fixed point or add another prior.
  member_values <- seq(-.15, .25, length.out = 51L)
  reference <- gcp_one_step_reference(prior_mean = .1, prior_sd = .3,
    probability = .2, response_scale = .3, member_scale = .8, members = member_values)
  log_prior <- function(t) stats::dnorm(t, .1, .3, log = TRUE)
  for (t in c(-.1, 0, .1, .2, .3)) {
    a <- gic_al_member_target(.4, t, constant, .3, .2,
      matrix(member_values, nrow = 1L), function(h, path, theta) theta,
      .8, log_prior)
    density_theta <- exp(a$log_target - stats::dnorm(.4, log = TRUE) - reference$log_member_evidence)
    close(density_theta, reference$parameter_density(t), 1e-8)
  }
  close(reference$coefficient_response_covariance, reference$parameter_variance, 1e-12)
  ok(reference$parameter_variance > 0)
  empty_reference <- gcp_one_step_reference(prior_mean = .1, prior_sd = .3,
    probability = .2, response_scale = .3, member_scale = .8)
  close(empty_reference$parameter_mean, .1, 1e-9)
  close(empty_reference$parameter_variance, .09, 1e-9)

  # MQ: separate path vectors and one coupled historical target. A common-Y
  # product, or including the historical target once per level, would fail.
  coupled <- function(t) sum(stats::dnorm(t, log = TRUE)) + stats::dnorm(t[2L] - t[1L], 0, .4, log = TRUE)
  mq_locations <- list(function(h, past, t) t[1L] + if (h > 1L) .2 * tail(past, 1L) else 0,
    function(h, past, t) t[2L] + if (h > 1L) .3 * tail(past, 1L) else 0)
  mq_base <- matrix(c(.2, -.4, .5, .7), 2L, 2L)
  mq <- gic_al_mq_target(mq_base, c(-.1, .3), mq_locations, list(.2, .4), c(.2, .8),
    list(NULL, NULL), list(NULL, NULL), list(NULL, NULL), coupled)
  ok(identical(dim(mq$paths), c(2L, 2L)) && !identical(mq$paths[, 1L], mq$paths[, 2L]))
  ok(identical(mq$path_convention, "separate_path_per_probability"))
  close(mq$log_target, coupled(c(-.1, .3)) + sum(stats::dnorm(mq_base, log = TRUE)))
  close(mq$log_path_density + mq$log_abs_jacobian, mq$log_base_density, 1e-12)
  ok(mq$historical_factor_count == 1L && !mq$production_qualified)
  mq_uniform <- function(u, t) gic_al_mq_target(matrix(u, 1L, 2L), t,
    mq_locations, list(.2, exp(t[2L])), c(.2, .8), list(NULL, NULL),
    list(NULL, NULL), list(NULL, NULL), coupled, "uniform")
  for (t in list(c(-.1, .3), c(.2, -.4))) {
    integral_over_paths <- integral(function(u1) vapply(u1, function(a)
      integral(function(u2) vapply(u2, function(b)
        exp(mq_uniform(c(a, b), t)$log_target - coupled(t)), numeric(1L)), 0, 1),
      numeric(1L)), 0, 1)
    close(integral_over_paths, 1, 1e-9)
  }
  # With members, preserve all 51 factors in each separate level's likelihood.
  mq_members <- gic_al_mq_target(mq_base, c(-.1, .3), mq_locations, list(.2, .4), c(.2, .8),
    list(members, members), list(member_location, member_location), list(.4, .5), coupled)
  close(mq_members$log_target, coupled(c(-.1, .3)) + sum(vapply(mq_members$levels,
    function(x) x$log_member_likelihood + x$transformed$log_base_density, numeric(1L))))
  ok(sum(vapply(mq_members$levels, function(x) x$member_factor_count, integer(1L))) == 204L)

  # Fail closed rather than clipping endpoints, changing member counts or
  # accepting incompatible probability, support or callback definitions.
  fails(gic_al_forward(0, theta, nonlinear, .3, 0))
  fails(gic_al_forward(0, theta, nonlinear, .3, 1))
  fails(gic_al_forward(Inf, theta, nonlinear, .3))
  fails(gic_al_forward(.5, theta, nonlinear, 0))
  fails(gic_al_forward(.5, theta, nonlinear, -.3))
  fails(gic_al_forward(c(0, .5), theta, nonlinear, .3, base_measure = "uniform"))
  fails(gic_al_forward(c(.5, 1), theta, nonlinear, .3, base_measure = "uniform"))
  fails(gic_al_forward(.5, theta, function(h, past, t) c(0, 1), .3))
  fails(gic_al_forward(.5, theta, function(h, past, t) NaN, .3))
  fails(gic_al_quantile_logs(log(.3), log(.8)))
  fails(gic_al_quantile(1))
  fails(gic_al_inverse(1e6, 0, constant, .3, .2, "uniform"))
  fails(gic_al_member_target(c(-.4, .7), theta, nonlinear, .3, .2,
    members[, -1L], member_location, .4, historical))
  fails(gic_al_member_target(c(-.4, .7), theta, nonlinear, .3, .2,
    matrix(NA_real_, 2L, 51L), member_location, .4, historical))
  fails(gic_al_mq_target(mq_base, theta, mq_locations, list(.2, .4), c(.8, .2),
    list(NULL, NULL), list(NULL, NULL), list(NULL, NULL), historical))
  cat(sprintf("GLOFAS_INNOVATION_COORDINATES_PASS checks=%d original_reads=0 fits=0 production_qualified=FALSE family=AL\n", checks))
})
