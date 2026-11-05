# Generated optimizer and gradient checks. No authentic data or model launch.
local({
  original_kind <- RNGkind()
  original_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(original_kind))
    if (is.null(original_seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", original_seed, .GlobalEnv)
  }, add = TRUE)
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  near <- function(x, y, tol = 1e-8) ok(max(abs(x - y)) < tol)
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  contract <- function(p, label = "generated_Gaussian") gcpopt_input_contract(paste0("eta", seq_len(p)),
    "caller_defined_transformed_parameter_vector_with_Jacobian_once", list(case = label),
    c(generated_source = gcpopt_hash(label)))
  zero <- function(eta, seed) list(log_estimate = 0, complete = TRUE,
    diagnostic_thresholds_passed = TRUE, callback_calls = 0L)
  gaussian <- function(target_mean, covariance) {
    P <- solve(covariance); d <- length(target_mean); logdet <- as.numeric(determinant(covariance, logarithm = TRUE)$modulus)
    function(mean, log_sd, factor) {
      L <- if (is.null(factor)) diag(d) else factor
      s2 <- exp(2 * log_sd); curvature <- diag(t(L) %*% P %*% L)
      displacement <- mean - target_mean
      value <- -.5 * (logdet + as.numeric(crossprod(displacement, P %*% displacement)) + sum(s2 * curvature)) +
        .5 * d + sum(log_sd) + as.numeric(determinant(L, logarithm = TRUE)$modulus)
      list(value = value, gradient_mean = as.numeric(-P %*% displacement), gradient_log_sd = 1 - s2 * curvature)
    }
  }

  # Correct affine Gaussian score and analytic entropy. Independent reward
  # baselines produce an unbiased sample covariance; constant reward vanishes.
  set.seed(84); epsilon <- matrix(rnorm(64), 32L, 2L)
  mean <- c(.2, -.3); log_sd <- c(-.2, .1)
  L <- matrix(c(1, .4, 0, 1.2), 2L, 2L)
  constant <- gcpopt_score_gradient(mean, log_sd, L, epsilon, rep(7, 32L))
  near(constant$gradient, c(0, 0, 1, 1), 1e-13)
  near(constant$mcse, rep(0, 4L), 1e-12)
  no_entropy <- gcpopt_score_gradient(mean, log_sd, L, epsilon, rep(7, 32L), include_entropy = FALSE)
  near(no_entropy$gradient, rep(0, 4L), 1e-13)
  ok(identical(constant$mcse_method, "delete_one_jackknife_independent_outer_draws"))
  reject(gcpopt_score_gradient(mean, log_sd, L, epsilon, rep(7, 32L), baseline = "same_draw"))
  target_mean <- c(.5, -.4); covariance <- matrix(c(1, .3, .3, 1.4), 2L)
  h <- gaussian(target_mean, covariance)
  set.seed(38); epsilon <- matrix(rnorm(60000), 30000L, 2L)
  draws <- sweep(sweep(epsilon, 2L, exp(log_sd), `*`) %*% t(L), 2L, mean, `+`)
  P <- solve(covariance)
  rewards <- -.5 * rowSums(((sweep(draws, 2L, target_mean)) %*% P) * sweep(draws, 2L, target_mean))
  gradient <- gcpopt_score_gradient(mean, log_sd, L, epsilon, rewards)
  analytic <- h(mean, log_sd, L)
  ok(all(abs(gradient$gradient - c(analytic$gradient_mean, analytic$gradient_log_sd)) < 5 * gradient$mcse + .01))

  # Real deterministic optimization in a correctly whitened correlated family.
  ctl <- gcpopt_control(max_iterations = 500L, minimum_iterations = 20L, learning_rate = .05,
    gradient_tolerance = 2e-4, gradient_mcse_tolerance = 1e-8,
    step_tolerance = 1e-4, objective_tolerance = 1e-7, stable_iterations = 4L)
  factor <- t(chol(covariance)); rng <- .Random.seed
  fit <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = c(-.6, .8),
    initial_log_sd = c(-.6, .4), factor = factor, control = ctl,
    input_contract = contract(2), analytic_historical = h)
  ok(identical(rng, .Random.seed))
  ok(fit$stopping_criteria_met && fit$completed_iterations > 20L)
  near(fit$mean, target_mean, 5e-4)
  near(fit$log_sd, c(0, 0), 5e-4)
  near(fit$marginal_variance, diag(covariance), 1e-3)
  near(fit$last_gradient$gradient, c(fit$last_gradient$gradient_mean, fit$last_gradient$gradient_log_sd), 1e-15)
  ok(tail(fit$history$objective, 1L) > fit$history$objective[1L] + .5)
  ok(!fit$posterior_accuracy_qualified && !fit$production_launch_authorized && fit$original_reads == 0L)
  ok(fit$all_parameter_dimensions_optimized && !fit$historical_parameters_frozen)
  repeat_fit <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = c(-.6, .8),
    initial_log_sd = c(-.6, .4), factor = factor, control = ctl,
    input_contract = contract(2), analytic_historical = h)
  near(repeat_fit$mean, fit$mean, 1e-15)
  near(repeat_fit$log_sd, fit$log_sd, 1e-15)
  # Mean updates use current q-standard-deviation units. Rescaling a physical
  # coordinate by 1e-3 therefore does not create a 0.03-unit mean oscillation.
  unit <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = 5, initial_log_sd = log(2),
    control = ctl, input_contract = contract(1, "unit_Normal"),
    analytic_historical = gaussian(0, matrix(1,1,1)))
  small_unit <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = .005, initial_log_sd = log(.002),
    control = ctl, input_contract = contract(1, "scaled_Normal"),
    analytic_historical = gaussian(0, matrix(1e-6,1,1)))
  ok(unit$stopping_criteria_met && small_unit$stopping_criteria_met)
  near(small_unit$mean / .001, unit$mean, 1e-8)
  near(small_unit$log_sd - log(.001), unit$log_sd, 1e-8)
  ok(identical(small_unit$mean_update_coordinates, "local_variational_standard_deviation_units_L_diag_sd"))

  # The identity-factor family does not learn arbitrary correlation. Its
  # reverse-KL variances are 1/P_jj, not the exact marginal variances.
  diagonal <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = c(-.6, .8),
    initial_log_sd = c(-.6, .4), control = ctl, input_contract = contract(2), analytic_historical = h)
  ok(diagonal$stopping_criteria_met)
  near(diagonal$marginal_variance, 1 / diag(P), 1e-3)
  ok(max(abs(diagonal$marginal_variance - diag(covariance))) > .05)
  ok(grepl("fixed_affine_factor", diagonal$family, fixed = TRUE))

  # Transformed inverse-gamma scale: target includes +eta exactly once. A
  # Gaussian eta factor has a known variational optimum, not an exact IG law.
  a <- 4; b <- .3
  ig_historical <- function(mean, log_sd, factor) {
    stopifnot(is.null(factor)); s2 <- exp(2 * log_sd)
    exp_inverse_scale <- exp(-mean[2L] + .5 * s2[2L])
    theta_term <- -.5 * ((s2[1L] + (mean[1L] - .1)^2) / .2^2 - 1 + log(.2^2 / s2[1L]))
    eta_term <- a * log(b) - lgamma(a) - a * mean[2L] - b * exp_inverse_scale +
      .5 * (1 + log(2 * pi)) + log_sd[2L]
    list(value = theta_term + eta_term,
      gradient_mean = c(-(mean[1L] - .1) / .2^2, -a + b * exp_inverse_scale),
      gradient_log_sd = c(1 - s2[1L] / .2^2, 1 - b * exp_inverse_scale * s2[2L]))
  }
  scale_fit <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = c(.5, -1.5),
    initial_log_sd = c(-.8, -.2), control = ctl, input_contract = contract(2, "Normal_theta_IG_scale"),
    analytic_historical = ig_historical)
  ok(scale_fit$stopping_criteria_met)
  near(scale_fit$mean, c(.1, log(b / a) + 1 / (2 * a)), 5e-4)
  near(scale_fit$log_sd, c(log(.2), -.5 * log(a)), 5e-4)
  approximate_scale_mean <- exp(scale_fit$mean[2L] + .5 * exp(2 * scale_fit$log_sd[2L]))
  ok(abs(approximate_scale_mean - b / (a - 1)) > .002)
  ok(!scale_fit$posterior_accuracy_qualified)

  # Generic score route genuinely improves a proper target, even if noisy
  # gradient/stopping criteria are not met before the declared iteration cap.
  generic_ctl <- gcpopt_control(max_iterations = 250L, minimum_iterations = 30L,
    batch_size = 256L, max_evaluations = 200000L, learning_rate = .03)
  generic <- gcpopt_optimize(log_historical = function(x) sum(dnorm(x, log = TRUE)),
    log_evidence_estimate = zero, initial_mean = 1.8, initial_log_sd = -1,
    control = generic_ctl, input_contract = contract(1))
  ok(generic$completed_iterations > 100L && is.null(generic$failure))
  ok(abs(generic$mean) < .12 && abs(exp(generic$log_sd) - 1) < .12)
  exact_KL <- function(m, ls) .5 * (m^2 + exp(2 * ls) - 1 - 2 * ls)
  ok(exact_KL(generic$mean, generic$log_sd) < exact_KL(1.8, -1) / 20)
  ok(!generic$posterior_accuracy_qualified)

  # Member information updates the parameter distribution; the historical
  # distribution is not fixed while only conditional future paths change.
  evidence <- function(eta, seed) list(log_estimate = dnorm(1.5, eta[1L], .5, log = TRUE),
    complete = TRUE, diagnostic_thresholds_passed = TRUE, callback_calls = 0L)
  future_ctl <- generic_ctl; future_ctl$max_iterations <- 350L; future_ctl$max_evaluations <- 300000L
  posterior <- gcpopt_optimize(log_evidence_estimate = evidence, initial_mean = 0, initial_log_sd = 0,
    control = future_ctl, input_contract = contract(1, "Gaussian_member_parameter_update"),
    analytic_historical = gaussian(0, matrix(1, 1L, 1L)))
  near(posterior$mean, 1.2, .08)
  near(posterior$marginal_variance, .2, .05)
  ok(posterior$mean > 1 && !posterior$historical_parameters_frozen)

  # Large identity-factor inventory is supported without allocating a dense I.
  many_ctl <- gcpopt_control(max_iterations = 3L, minimum_iterations = 1L, stable_iterations = 2L,
    batch_size = 4L, gradient_tolerance = 1e-8, gradient_mcse_tolerance = 1e-8,
    step_tolerance = 1e-8, objective_tolerance = 1e-8)
  many <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = rep(0, 7510L),
    initial_log_sd = rep(0, 7510L), control = many_ctl, input_contract = contract(7510L),
    analytic_historical = function(mean, log_sd, factor) {
      stopifnot(is.null(factor))
      list(value = -.5 * sum(mean^2 + exp(2 * log_sd) - 1 - 2 * log_sd),
        gradient_mean = -mean, gradient_log_sd = 1 - exp(2 * log_sd))
    })
  ok(many$stopping_criteria_met && length(many$mean) == 7510L && is.null(many$factor))
  ok(!many$production_launch_authorized)

  # Failed/partial evidence, native-style budgets and invalid coordinate
  # contracts never become a successful optimizer or posterior qualification.
  tiny <- many_ctl; tiny$max_evaluations <- 1L
  limited <- gcpopt_optimize(log_evidence_estimate = zero, initial_mean = 0, initial_log_sd = 0,
    control = tiny, input_contract = contract(1), analytic_historical = gaussian(0, matrix(1,1,1)))
  ok(!limited$stopping_criteria_met && limited$completed_iterations == 0L && !is.null(limited$failure))
  invalid_inner <- function(eta, seed) list(log_estimate = 0, complete = TRUE,
    diagnostic_thresholds_passed = FALSE, callback_calls = 0L)
  failed <- gcpopt_optimize(log_historical = function(x) sum(dnorm(x, log = TRUE)),
    log_evidence_estimate = invalid_inner, initial_mean = 0, initial_log_sd = 0,
    control = many_ctl, input_contract = contract(1))
  ok(!failed$stopping_criteria_met && failed$completed_iterations == 0L && !is.null(failed$failure))
  evil_rng <- function(eta, seed) { runif(1); zero(eta, seed) }
  before <- .Random.seed
  bad_rng <- gcpopt_optimize(log_historical = function(x) sum(dnorm(x, log = TRUE)),
    log_evidence_estimate = evil_rng, initial_mean = 0, initial_log_sd = 0,
    control = many_ctl, input_contract = contract(1))
  ok(grepl("outer RNG", bad_rng$failure, fixed = TRUE) && identical(before, .Random.seed))
  bad <- many_ctl; bad$frozen_dimensions <- 1L
  reject(gcpopt_validate_control(bad))
  bad <- contract(1); bad$jacobian_policy <- "insert_twice"
  reject(gcpopt_optimize(log_historical = function(x) dnorm(x, log = TRUE), log_evidence_estimate = zero,
    initial_mean = 0, initial_log_sd = 0, control = many_ctl, input_contract = bad))
  reject(gcpopt_optimize(log_historical = function(x) dnorm(x, log = TRUE), log_evidence_estimate = zero,
    initial_mean = 0, initial_log_sd = 0, control = many_ctl, input_contract = contract(1),
    analytic_historical = gaussian(0, matrix(1,1,1))))
  reject(gcpopt_factor(matrix(0, 2L, 2L), 2L))
  reject(gcpopt_score_gradient(0, 0, epsilon = matrix(NA_real_, 4L, 1L), rewards = rep(0, 4L)))
  ok(!limited$production_launch_authorized && !failed$reference_qualified)
  cat(sprintf("GLOFAS_COLLAPSED_PARAMETER_OPTIMIZER_PASS checks=%d original_reads=0 authentic_fits=0 production_qualified=FALSE\n", checks))
})
