# Generated bounded AL particle/parameter calculations. No authentic objects.
local({
  original_kind <- RNGkind()
  original_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(original_kind))
    if (is.null(original_seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", original_seed, .GlobalEnv)
  }, add = TRUE)
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_vi.R", local = TRUE)
  source("scripts/diagnostics/glofas_coupled_parameter_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  near <- function(x, y, tol = 1e-10) ok(max(abs(x - y)) < tol)
  rejects <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  mu <- function(h, past, p) p$theta + if (h > 1L) .2 * tail(past, 1L) else 0
  sigma <- function(h, past, p) p$sigma
  member_mu <- function(h, past, p) p$theta + if (h > 1L) .35 * tail(past, 1L) else 0
  parameters <- list(theta = .1, sigma = .3)
  limits <- list(max_horizon = 28L, max_particles = 4096L, max_calls = 100000L)
  gates <- list(min_ess = 2, min_unique_ancestors = 2L)
  base <- list(location = mu, scale = sigma, member_location = member_mu,
    member_scale = .8, members = NULL, horizon = 2L, probability = .5,
    particles = 64L, ess_fraction = .5, limits = limits, gates = gates)
  run <- function(args = base, p = parameters, seed = 2026110501L)
    do.call(gcpv_smc, c(list(parameters = p, seed = seed), args))

  set.seed(481); rng <- .Random.seed; kind <- RNGkind()
  empty <- run()
  ok(identical(rng, .Random.seed) && identical(kind, RNGkind()))
  ok(empty$complete && empty$diagnostic_thresholds_passed)
  ok(identical(empty$log_normalizer_estimate, 0) && identical(empty$normalizer_estimate, 1))
  ok(all(empty$member_weights == 1) && empty$member_factor_evaluations == 0L)
  ok(identical(empty$paths, run()$paths))
  ok(empty$callback_calls == 2L * 64L * 2L)
  ok(all(empty$diagnostics$effective_sample_size >= 64 - 1e-9))
  ok(all(vapply(gcpv_flags(), function(x) identical(x, FALSE) || identical(x, 0L), logical(1L))))

  # Strictly past-only locations: the h=1 callbacks receive an empty history,
  # h=2 receives one value. The likelihood is not evaluated at current Y_h.
  checked_mu <- function(h, past, p) { stopifnot(length(past) == h - 1L); mu(h, past, p) }
  checked_G <- function(h, past, p) { stopifnot(length(past) == h - 1L); member_mu(h, past, p) }
  members <- rbind(seq(-.08, .08, length.out = 51L), seq(.08, .2, length.out = 51L))
  args <- base; args$members <- members; args$location <- checked_mu; args$member_location <- checked_G
  a <- run(args)
  ok(a$complete && a$member_count == 51L && all(a$member_weights == 1))
  ok(a$member_factor_evaluations == 51L * 64L * 2L)
  ok(a$callback_calls == 4L * 64L * 2L)
  ok(a$expected_log_bound && !a$realized_log_estimate_is_a_bound && !a$resampling_gradient_implemented)

  # One horizon: G_1 is independent of the newly generated Y_1, so every
  # positive-particle estimator equals the exact product of 51 densities.
  one <- args; one$horizon <- 1L; one$members <- members[1L, , drop = FALSE]
  exact_one <- sum(gic_al_log_density(one$members[1L, ], parameters$theta, .5, .8))
  for (n in c(2L, 17L, 64L)) {
    one$particles <- n
    out <- run(one)
    near(out$log_normalizer_estimate, exact_one, 1e-12)
    ok(!out$reference_qualified && !out$production_qualified && out$model_fits == 0L)
  }
  # Finite log normalizers need not be representable after exponentiation.
  # The exact H1 potential is constant across particles, for both extremes.
  for (logZ in c(-1000, 1000)) {
    extreme <- one; extreme$members <- matrix(0, 1L, 51L)
    extreme$member_location <- function(h, past, p) 0
    extreme$member_scale <- .25 * exp(-logZ / 51)
    out <- run(extreme)
    near(out$log_normalizer_estimate, logZ, 1e-10)
    ok(out$complete && is.na(out$normalizer_estimate))
    ok(identical(out$normalizer_scale_status, if (logZ < 0)
      "underflow_log_normalizer_only" else "overflow_log_normalizer_only"))
    near(sum(out$weights), 1, 1e-14)
  }

  # Independent one-dimensional quadrature for H=2. Y_2 integrates to one;
  # split the AL kink and every member-likelihood kink explicitly.
  member_log <- function(y) vapply(y, function(x)
    sum(gic_al_log_density(members[2L, ], parameters$theta + .35 * x, .5, .8)), numeric(1L))
  knots <- sort(unique(c(parameters$theta, (members[2L, ] - parameters$theta) / .35)))
  centre <- max(member_log(knots))
  integrate_piecewise <- function(upper = Inf) {
    grid <- c(-Inf, knots[knots < upper], upper)
    sum(vapply(seq_len(length(grid) - 1L), function(j) stats::integrate(function(y)
      exp(gic_al_log_density(y, parameters$theta, .5, parameters$sigma) + member_log(y) - centre),
      grid[j], grid[j + 1L], rel.tol = 1e-10, abs.tol = 1e-12, subdivisions = 200L)$value, numeric(1L)))
  }
  total <- integrate_piecewise()
  exact_logZ <- exact_one + centre + log(total)
  cdf_at <- .15; exact_cdf <- integrate_piecewise(cdf_at) / total
  independent <- gcpr_conditional(parameters$theta, parameters$sigma, members,
    p = .5, member_scale = .8, lag = .35, horizon = 2L)
  near(independent$log_evidence, exact_logZ, 1e-10)
  oracle <- function(phi) gcpr_conditional(phi[1L], exp(phi[2L]), members,
    p = .5, member_scale = .8, lag = .35, horizon = 2L)$log_evidence
  derivative <- gcpv_finite_difference(oracle, c(parameters$theta, log(parameters$sigma)))$gradient
  near(derivative, independent$fisher_gradient, 1e-6)
  near(derivative, independent$reparameterized_gradient, 1e-6)
  args$particles <- 256L; args$ess_fraction <- .8
  repeats <- 24L
  estimates <- lapply(seq_len(repeats), function(j) run(args, seed = 2026110500L + j))
  ok(all(vapply(estimates, function(x) x$complete, logical(1L))))
  ratios <- exp(vapply(estimates, function(x) x$log_normalizer_estimate, numeric(1L)) - exact_logZ)
  mcse_ratio <- stats::sd(ratios) / sqrt(repeats)
  ok(abs(mean(ratios) - 1) < 5 * mcse_ratio + .01)
  logs <- log(ratios)
  # The finite empirical mean can fluctuate above its expectation; do not
  # mistake Jensen's expected-log bound for a per-run inequality.
  ok(mean(logs) <= 4 * stats::sd(logs) / sqrt(repeats) + .005)
  ok(any(logs > 0))
  # An unbiased evidence estimator need not preserve the parameter posterior
  # after optimizing a finite-particle expected-log bound. Both exact parameter
  # evidences are one, but only the second estimator has Monte Carlo variance.
  # This is not a production accuracy/qualification test or an optimizer.
  exact_parameter_posterior <- c(.5, .5)
  estimates_A <- c(1, 1); estimates_B <- c(.5, 1.5)
  near(c(mean(estimates_A), mean(estimates_B)), c(1, 1), 1e-15)
  expected_log <- c(mean(log(estimates_A)), mean(log(estimates_B)))
  near(expected_log, c(0, .5 * log(.75)), 1e-15)
  finite_bound_optimum <- exp(expected_log - gcpv_logsumexp(expected_log))
  near(finite_bound_optimum[1L], 1 / (1 + sqrt(.75)), 1e-15)
  ok(max(abs(finite_bound_optimum - exact_parameter_posterior)) > .03)
  bound <- function(weights) sum(weights * (log(.5) - log(weights) + expected_log))
  ok(bound(finite_bound_optimum) > bound(exact_parameter_posterior) && bound(finite_bound_optimum) < 0)
  cdfs <- vapply(estimates, function(x) sum(x$weights * (x$paths[, 1L] <= cdf_at)), numeric(1L))
  ok(abs(mean(cdfs) - exact_cdf) < 5 * stats::sd(cdfs) / sqrt(repeats) + .02)
  ok(any(vapply(estimates, function(x) any(x$diagnostics$resampled), logical(1L))))

  # Strongly degenerate but complete output is retained, not qualified.
  narrow <- args; narrow$particles <- 64L; narrow$member_scale <- .001
  narrow$gates <- list(min_ess = 32, min_unique_ancestors = 32L)
  bad <- run(narrow)
  ok(bad$complete && !bad$diagnostic_thresholds_passed && all(is.finite(bad$paths)))
  ok(min(bad$diagnostics$effective_sample_size) < 32)
  ok(!bad$reference_qualified && !bad$publication_authorized)
  partial_args <- base; partial_args$limits$max_calls <- 1L
  partial <- run(partial_args)
  ok(!partial$complete && !partial$diagnostic_thresholds_passed && !is.null(partial$failure))
  ok(partial$callback_calls <= 1L && is.na(partial$normalizer_estimate) && anyNA(partial$paths))
  faulty <- base; faulty$location <- function(h, past, p) stop("generated callback failure")
  out <- run(faulty)
  ok(!out$complete && grepl("generated callback failure", out$failure, fixed = TRUE))
  ok(identical(rng, .Random.seed))

  # Vary BOTH coefficient and scale. With no members, the normalized future
  # law contributes exactly zero to every parameter draw's log objective.
  params <- list(list(theta = -.2, sigma = .2), list(theta = .1, sigma = .3),
    list(theta = .4, sigma = .7), list(theta = .2, sigma = 1.1))
  prior <- function(p) stats::dnorm(p$theta, 0, .5, log = TRUE) +
    3 * log(.6) - lgamma(3) - 4 * log(p$sigma) - .6 / p$sigma
  seeds <- 2026110601:2026110604
  uncertain <- gcpv_joint_objective(params, prior, prior, base, seeds)
  ok(uncertain$complete && !uncertain$parameters_frozen && !uncertain$historical_parameters_optimized)
  near(uncertain$value, 0, 1e-15)
  ok(all(vapply(uncertain$conditional_records, function(x) identical(x$normalizer_estimate, 1), logical(1L))))
  one$particles <- 32L
  conditioned <- gcpv_joint_objective(params, prior, prior, one, seeds)
  exact_components <- vapply(params, function(p) sum(gic_al_log_density(members[1L, ], p$theta, .5, .8)), numeric(1L))
  near(conditioned$value, mean(exact_components), 1e-12)
  ok(diff(range(conditioned$parameter_components)) > 1)
  posterior_weights <- exp(exact_components - gcpv_logsumexp(exact_components))
  ok(abs(sum(posterior_weights * vapply(params, function(p) p$theta, numeric(1L))) -
    mean(vapply(params, function(p) p$theta, numeric(1L)))) > .03)
  # A coupled historical distribution is passed as complete parameter pairs,
  # never replaced by independently combined posterior marginals. A member
  # likelihood involving theta can consequently update sigma as well.
  joint_historical <- function(p) stats::dnorm(p$theta, .1 + .4 * log(p$sigma), .6, log = TRUE) +
    3 * log(.6) - lgamma(3) - 4 * log(p$sigma) - .6 / p$sigma
  coupled <- gcpv_joint_objective(params, joint_historical, joint_historical, one, seeds)
  ok(all(vapply(seq_along(params), function(j)
    identical(coupled$conditional_records[[j]]$parameters, params[[j]]), logical(1L))))
  near(coupled$parameter_components, exact_components, 1e-12)
  sigma_values <- vapply(params, function(p) p$sigma, numeric(1L))
  ok(abs(sum(posterior_weights * sigma_values) - mean(sigma_values)) > .05)

  # Same target/proposal measures: changing sigma to log(sigma) contributes
  # its Jacobian exactly once, never inside the particle integrator.
  q_log_sigma <- function(p) stats::dnorm(p$theta, .1, .6, log = TRUE) +
    stats::dnorm(log(p$sigma), -.7, .5, log = TRUE)
  q_physical <- function(p) q_log_sigma(p) - log(p$sigma)
  p_log_sigma <- function(p) prior(p) + log(p$sigma)
  physical <- gcpv_joint_objective(params, prior, q_physical, base, seeds)
  logscale <- gcpv_joint_objective(params, p_log_sigma, q_log_sigma, base, seeds)
  near(physical$value, logscale$value, 1e-12)
  double_jacobian <- gcpv_joint_objective(params, function(p) p_log_sigma(p) + log(p$sigma),
    q_log_sigma, base, seeds)
  ok(abs(double_jacobian$value - logscale$value) > .1)
  partial_joint <- gcpv_joint_objective(params, prior, prior, base, seeds, max_total_calls = 5L)
  ok(!partial_joint$complete && !partial_joint$diagnostic_thresholds_passed && is.na(partial_joint$value))

  # Deterministic, differentiable Normal-parameter / AL-member objective.
  # This oracle includes uncertainty in theta, not a likelihood at E(theta).
  # It is NOT a finite-difference shortcut through random resampling decisions.
  observations <- members[1L, ]; tau <- .5; sigma_G <- .8
  exact_objective <- function(phi) {
    m <- phi[1L]; sd <- exp(phi[2L]); d <- (m - observations) / sd
    expected_absolute <- 2 * sd * stats::dnorm(d) + (m - observations) * (2 * stats::pnorm(d) - 1)
    -.5 * ((sd^2 + m^2) / tau^2 - 1 + log(tau^2 / sd^2)) +
      length(observations) * log(.25 / sigma_G) - sum(expected_absolute) / (2 * sigma_G)
  }
  phi <- c(.12, log(.25)); sd <- exp(phi[2L]); d <- (phi[1L] - observations) / sd
  exact_gradient <- c(-phi[1L] / tau^2 - sum(2 * stats::pnorm(d) - 1) / (2 * sigma_G),
    1 - sd^2 / tau^2 - sum(2 * sd * stats::dnorm(d)) / (2 * sigma_G))
  gradient <- gcpv_finite_difference(exact_objective, phi)
  near(gradient$gradient, exact_gradient, 1e-7)
  ok(!gradient$production_optimizer && !gradient$resampling_gradient_implemented)
  no_member_logZ <- function(phi) run(base, list(theta = phi[1L], sigma = exp(phi[2L])))$log_normalizer_estimate
  near(gcpv_finite_difference(no_member_logZ, c(.1, log(.3)))$gradient, c(0, 0), 1e-15)

  # Invalid policies/support are not silently weakened to make a run finish.
  invalid <- base; invalid$members <- matrix(0, 2L, 50L); rejects(run(invalid))
  invalid <- base; invalid$particles <- 5000L; rejects(run(invalid))
  invalid <- base; invalid$horizon <- 29L; rejects(run(invalid))
  invalid <- base; invalid$seed <- 1; rejects(do.call(gcpv_smc, c(list(parameters = parameters), invalid, list(unknown = 1))))
  rejects(gcpv_joint_objective(params, prior, prior, base, seeds, parameter_weights = rep(.2, 4L)))
  rejects(gcpv_finite_difference(exact_objective, phi, objective_scope = "frozen_random_resampling"))
  cat(sprintf("GLOFAS_COLLAPSED_PARTICLE_VI_PASS checks=%d generated_replicates=%d original_reads=0 optimizer=FALSE production_qualified=FALSE\n",
    checks, repeats))
})
