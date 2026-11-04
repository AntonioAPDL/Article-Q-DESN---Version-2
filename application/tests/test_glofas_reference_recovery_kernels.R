# Generated numeric qualification only. No retained/original RDS or authentic
# feature callback is read, and no application fit or scientific run is made.
local({
  source("scripts/diagnostics/glofas_al_path_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_reference_recovery_kernels.R", local = TRUE)
  reject <- function(expr) stopifnot(inherits(try(force(expr), silent = TRUE), "try-error"))
  fixture <- function(H = 1L, M = 3L, nonlinear = FALSE) {
    contract <- list(mode = "generated", likelihood_family = "al", p = .5,
      sigma_y = .15, sigma_g = .3, issued = matrix(rep(c(-.1, .2), length.out = H), H, M),
      member_weights = matrix(1, H, M), forecast_dates = as.Date("2000-01-01") + seq_len(H),
      origin_date = as.Date("2000-01-01"), known_baseline = rep(0, H),
      parameter_id = paste("generated_fixed", H, M, nonlinear),
      feature_id = paste("generated_nonlinear", H, nonlinear), coefficient_covariance = matrix(0, 2, 2),
      truth_access = "forbidden", max_callback_calls = 1000000L, max_jacobian_calls = 1L,
      ensemble_location_convention = "total_reference_plus_discrepancy_plus_known_baseline")
    callback <- function(y) {
      r <- g <- numeric(H)
      if (nonlinear) { r[2L] <- .35 * tanh(y[1L]); g[2L] <- .25 * tanh(y[1L]) }
      list(reference_location = r, ensemble_location = g)
    }
    gapr_new_target(callback, contract)
  }
  control <- function(kernel, warmup = 300L, samples = 4000L) list(
    warmup = warmup, samples = samples, max_evaluations = 100000L, max_wall_seconds = 60,
    adapt_warmup = TRUE, rhat_max = 1.01, min_ess = 400, max_quantile_mcse = .03, kernel = kernel)
  calibration <- function(H = 1L) {
    z <- array(stats::rnorm(2000L * 4L * H, sd = sqrt(.18)), c(2000L, 4L, H))
    if (H == 2L) z[, , 2L] <- .35 * tanh(z[, , 1L]) + z[, , 2L]
    grr_calibrate_proposal(z, require_authentic_shape = FALSE)
  }
  set.seed(411)
  # The authentic-shape contract is tested on generated finite numbers only.
  shape <- c(20000L, 4L, 28L)
  generated <- array(stats::rnorm(prod(shape)), shape)
  cal <- grr_calibrate_proposal(generated)
  X <- matrix(generated, ncol = 28L); S <- stats::cov(X)
  stopifnot(identical(cal$role, "MCMC_PROPOSAL_ONLY"),
    identical(cal$input_dimensions, shape), cal$pooled_observations == 80000L,
    max(abs(cal$pooled_mean - colMeans(X))) < 1e-14,
    max(abs(cal$pooled_covariance - S)) < 1e-14,
    max(abs(cal$proposal_covariance - (.95 * S + .05 * diag(diag(S))))) < 1e-14,
    max(abs(tcrossprod(cal$root_covariance) - cal$proposal_covariance)) < 1e-12,
    !cal$spd_floor_applied, identical(cal$fixed_model_updates, FALSE),
    all(unlist(cal[c("theta_updates", "prior_updates", "source_scale_updates", "feature_updates")]) == 0))
  rm(generated, X, S, cal)
  singular <- array(0, c(20L, 4L, 2L)); singular[, , 1L] <- matrix(seq_len(80L), 20L, 4L)
  floored <- grr_calibrate_proposal(singular, FALSE)
  stopifnot(floored$spd_floor_applied, floored$floored_eigenvalues == 1L,
    abs(floored$spd_floor - 1e-10 * sum(diag(floored$pooled_covariance)) / 2) < 1e-20,
    min(eigen(floored$proposal_covariance, symmetric = TRUE)$values) >= .999999 * floored$spd_floor)
  reject(grr_calibrate_proposal(singular))
  reject(grr_calibrate_proposal(array(0, c(20L, 4L, 1L)), FALSE))
  bad <- singular; bad[1L] <- NA_real_; reject(grr_calibrate_proposal(bad, FALSE))
  reject(grr_calibrate_proposal(singular[, 1:3, , drop = FALSE], FALSE))

  # Multivariate-t scale is not its covariance: with nu=5 the proposal uses
  # scale=(nu-2)/nu*C. Validate the density independently against one-dimensional
  # stats::dt and a direct two-dimensional quadratic-form formula.
  for (df in c(3, 5, 11)) for (value in c(-10, -.2, 0, 1, 8)) {
    scale <- matrix(.7, 1L, 1L); location <- .3
    expected <- stats::dt((value - location) / sqrt(scale[1L]), df, log = TRUE) - log(sqrt(scale[1L]))
    stopifnot(abs(grr_log_student_t(value, location, scale, df) - expected) < 1e-12)
  }
  scale <- matrix(c(1, .2, .2, 2), 2L); location <- c(.1, -.2); value <- c(1.1, .3); df <- 5
  delta <- drop(crossprod(value - location, solve(scale, value - location)))
  direct <- lgamma((df + 2) / 2) - lgamma(df / 2) - log(df * pi) -
    .5 * as.numeric(determinant(scale, logarithm = TRUE)$modulus) - (df + 2) / 2 * log1p(delta / df)
  stopifnot(abs(grr_log_student_t(value, location, scale, df) - direct) < 1e-12)
  reject(grr_log_student_t(value, location, matrix(c(1, 2, 2, 1), 2L)))

  # Detailed balance is checked for each separately reversible component,
  # including the direction of the independence Hastings correction. Their
  # state-independent half/half mixture then inherits detailed balance.
  logpi <- function(x) stats::dnorm(x, .4, .9, log = TRUE)
  logq <- function(x) grr_log_student_t(x, -.1, matrix(.7, 1L, 1L))
  for (x in c(-2, -.1, .3)) for (y in c(-.4, 1, 3)) {
    independent_xy <- logpi(x) + logq(y) + min(0, grr_log_mh_ratio(logpi(x), logpi(y), logq(x), logq(y)))
    independent_yx <- logpi(y) + logq(x) + min(0, grr_log_mh_ratio(logpi(y), logpi(x), logq(y), logq(x)))
    symmetric_xy <- logpi(x) + stats::dnorm(y, x, .8, log = TRUE) + min(0, grr_log_mh_ratio(logpi(x), logpi(y)))
    symmetric_yx <- logpi(y) + stats::dnorm(x, y, .8, log = TRUE) + min(0, grr_log_mh_ratio(logpi(y), logpi(x)))
    stopifnot(abs(independent_xy - independent_yx) < 1e-12,
      abs(symmetric_xy - symmetric_yx) < 1e-12,
      abs(.5 * exp(independent_xy) + .5 * exp(symmetric_xy) -
          .5 * exp(independent_yx) - .5 * exp(symmetric_yx)) < 1e-14)
    # Exact known-Normal independence proposal: q=pi gives acceptance one.
    stopifnot(abs(grr_log_mh_ratio(logpi(x), logpi(y), logpi(x), logpi(y))) < 1e-14,
      abs(grr_log_mh_ratio(logq(x), logq(y), logq(x), logq(y))) < 1e-14)
  }
  stopifnot(grr_log_mh_ratio(0, -Inf) == -Inf)

  # Scalar AL reference and nonlinear two-horizon reference are independently
  # integrated. Integrating normalized conditional Y2 removes its AL factor;
  # this is NOT a transformed innovation target or a location plug-in sampler.
  scalar <- fixture()
  scalar_reference <- gapr_one_dimensional_reference(function(y) gapr_log_target(scalar, y))
  scalar_expected <- c(.3 * log(.1), 0, -.3 * log(.1))
  stopifnot(max(abs(scalar_reference$quantiles - scalar_expected)) < 1e-8)
  nonlinear <- fixture(2L, 3L, TRUE)
  profile <- function(y) gapr_log_target(nonlinear, c(y, .35 * tanh(y)))
  splits <- c(0, atanh(.8))
  nonlinear_reference <- gapr_one_dimensional_reference(profile, splits)
  raw1 <- function(y) exp(-abs(y) / .3 - 3 * abs(.2 - .25 * tanh(y)) / .6)
  integrate_split <- function(f) {
    b <- c(-Inf, splits, Inf)
    sum(vapply(seq_len(length(b) - 1L), function(i)
      stats::integrate(f, b[i], b[i + 1L], rel.tol = 1e-10, subdivisions = 1000L)$value, numeric(1L)))
  }
  norm1 <- integrate_split(raw1)
  independent_reference <- gapr_one_dimensional_reference(function(y) log(raw1(y)), splits)
  stopifnot(max(abs(independent_reference$quantiles - nonlinear_reference$quantiles)) < 1e-8)
  al_cdf <- function(x) ifelse(x < 0, .5 * exp(pmin(x / .3, 0)), 1 - .5 * exp(pmin(-x / .3, 0)))
  cdf2 <- function(z) integrate_split(function(y) raw1(y) * al_cdf(z - .35 * tanh(y))) / norm1
  reference2 <- vapply(c(.05, .5, .95), function(p)
    stats::uniroot(function(z) cdf2(z) - p, c(-5, 5), tol = 1e-9)$root, numeric(1L))
  dep <- gapr_posterior_dependency()
  stopifnot(dep$available)
  for (kind in c("calibrated_random_walk", "mixture_random_walk_student_t")) {
    for (H in 1:2) {
      target <- fixture(as.integer(H), 3L, H == 2L)
      ctl <- control(kind)
      cal <- calibration(as.integer(H)); original_cal <- cal; original_condition <- target$contract
      starts <- matrix(rep(c(-.7, -.2, .2, .7), each = H), H, 4L)
      set.seed(7331); before_rng <- .Random.seed; before_kind <- RNGkind()
      sampled <- grr_sample_reference(target, starts, cal, ctl)
      stopifnot(identical(.Random.seed, before_rng), identical(RNGkind(), before_kind),
        identical(cal, original_cal), identical(target$contract, original_condition),
        identical(sampled$seeds, gapr_named_seeds(.5)),
        identical(dim(sampled$draws), c(ctl$samples, 4L, as.integer(H))),
        all(is.finite(sampled$draws)), sampled$conditional_reference_chains_completed == 4L,
        sampled$callback_evaluations == 4L * (1L + ctl$warmup + ctl$samples),
        sum(sampled$kernel_attempted) == 4L * (ctl$warmup + ctl$samples),
        sum(sampled$retained_kernel_counts$attempted) == 4L * ctl$samples,
        all(sampled$kernel_moved <= sampled$kernel_accepted),
        all(sampled$kernel_accepted <= sampled$kernel_attempted),
        sampled$scientific_runs == 0L, sampled$authentic_reads == 0L, sampled$full_parameter_refits == 0L)
      for (chain in 1:4) {
        state <- sampled$chain_states[[chain]]
        stopifnot(state$fully_completed, identical(state$initial_path, as.numeric(starts[, chain])),
          is.integer(state$initial_RNG_state), is.integer(state$final_RNG_state),
          !identical(state$initial_RNG_state, state$final_RNG_state),
          identical(state$final_path, as.numeric(sampled$draws[ctl$samples, chain, ])),
          state$frozen_proposal_factor == state$proposal_factor_at_sampling_start,
          all(sampled$proposal_factors[(ctl$warmup + 1L):(ctl$warmup + ctl$samples + 1L), chain] ==
            state$frozen_proposal_factor), !state$exact_resume_qualified,
          state$adaptation_updates <= ctl$warmup)
      }
      references <- if (H == 1L) matrix(scalar_expected, ncol = 1L) else
        cbind(nonlinear_reference$quantiles, reference2)
      for (h in seq_len(H)) {
        q <- as.numeric(stats::quantile(sampled$draws[, , h], c(.05, .5, .95), names = FALSE))
        mc <- as.numeric(posterior::mcse_quantile(matrix(sampled$draws[, , h], ctl$samples, 4L), probs = c(.05, .5, .95)))
        stopifnot(all(is.finite(mc)), all(abs(q - references[, h]) < 7 * mc + .02))
      }
      if (kind == "calibrated_random_walk") stopifnot(all(sampled$kernel_attempted[2L, ] == 0)) else
        stopifnot(all(sampled$kernel_attempted > 0), identical(sampled$mixture_weights, c(random_walk = .5, independence_student_t = .5)),
          max(abs(sampled$independence_scale - .6 * cal$proposal_covariance)) < 1e-14)
    }
  }

  # Fork/subset combination is exactly equivalent to the fixed-seed serial
  # run. A progress callback cannot perturb chain RNG, even if it draws random
  # numbers. It receives bounded metadata only, every 250 iterations and final.
  ctl <- control("mixture_random_walk_student_t", 100L, 400L)
  cal <- calibration(); starts <- matrix(c(-.7, -.2, .2, .7), 1L, 4L)
  events <- list()
  callback <- function(metadata) { events[[length(events) + 1L]] <<- metadata; stats::runif(17L); invisible(NULL) }
  serial <- grr_sample_reference(fixture(), starts, cal, ctl)
  with_progress <- grr_sample_reference(fixture(), starts, cal, ctl, callback)
  stopifnot(identical(serial$draws, with_progress$draws), identical(serial$chain_states, with_progress$chain_states),
    with_progress$progress_callback_calls == 8L, length(events) == 8L,
    identical(vapply(events, function(x) x$completed_iterations, integer(1L)), rep(c(250L, 500L), 4L)),
    all(vapply(events, function(x) !any(c("path", "draws", "density", "current_log_density") %in% names(x)), logical(1L))))
  parts <- lapply(1:4, function(chain) {
    part_control <- ctl; part_control$chain_ids <- chain
    grr_sample_reference(fixture(), starts, cal, part_control)
  })
  combined <- grr_combine_chains(parts[c(4, 2, 1, 3)], fixture(), ctl)
  transition_states <- function(states) lapply(states, function(s) { s$control$chain_ids <- NULL; s })
  stopifnot(identical(serial$draws, combined$draws),
    identical(transition_states(serial$chain_states), transition_states(combined$chain_states)),
    identical(serial$proposal_factors, combined$proposal_factors),
    identical(serial$kernel_attempted, combined$kernel_attempted),
    identical(serial$kernel_accepted, combined$kernel_accepted),
    combined$conditional_reference_chains_completed == 4L,
    combined$callback_evaluations == serial$callback_evaluations)
  reject(grr_combine_chains(parts[c(1, 1, 3, 4)], fixture(), ctl))
  changed <- parts; changed[[2L]]$seeds[[2L]] <- 1L
  reject(grr_combine_chains(changed, fixture(), ctl))
  changed <- parts; changed[[2L]]$condition$sigma_y <- .2
  reject(grr_combine_chains(changed, fixture(), ctl))
  changed <- parts; changed[[2L]]$control$kernel <- "calibrated_random_walk"
  reject(grr_combine_chains(changed, fixture(), ctl))
  changed <- parts; changed[[2L]]$calibration$pooled_mean <- 99
  reject(grr_combine_chains(changed, fixture(), ctl))
  bad_control <- ctl; bad_control$chain_ids <- c(1, 1)
  reject(grr_sample_reference(fixture(), starts, cal, bad_control))
  bad_control$chain_ids <- 1.5; reject(grr_sample_reference(fixture(), starts, cal, bad_control))
  bad_control <- ctl; bad_control$kernel <- "choose_favorable_kernel"
  reject(grr_sample_reference(fixture(), starts, cal, bad_control))

  # Budget-limited chains and all their partial draws/states remain visible.
  tiny <- ctl; tiny$max_evaluations <- 2L; tiny$chain_ids <- 1L
  set.seed(91); before_rng <- .Random.seed
  limited <- grr_sample_reference(fixture(), starts, cal, tiny)
  stopifnot(limited$status == "INCONCLUSIVE_BUDGET_LIMITED", !limited$qualified,
    limited$callback_evaluations == 2L, limited$chain_states[[1L]]$completed_iterations == 1L,
    !limited$chain_states[[1L]]$fully_completed, identical(.Random.seed, before_rng))
  partial_parts <- parts; partial_parts[[1L]] <- limited
  # Different per-worker hard limits are rejected, rather than silently merged.
  reject(grr_combine_chains(partial_parts, fixture(), ctl))
  same_limits <- tiny; same_limits$chain_ids <- NULL
  incomplete_parts <- lapply(1:4, function(chain) {
    local_control <- same_limits; local_control$chain_ids <- chain
    grr_sample_reference(fixture(), starts, cal, local_control)
  })
  incomplete <- grr_combine_chains(incomplete_parts, fixture(), same_limits)
  stopifnot(incomplete$status == "INCONCLUSIVE_CHAIN_EXECUTION", !incomplete$qualified,
    length(incomplete$chain_states) == 4L, all(vapply(incomplete$chain_states, function(x) !is.null(x), logical(1L))),
    identical(dim(incomplete$draws), c(ctl$samples, 4L, 1L)))
  wall <- ctl; wall$max_wall_seconds <- .001; wall$chain_ids <- 1L
  slow_target <- fixture(); fast_callback <- slow_target$callback
  slow_target$callback <- function(y) { Sys.sleep(.01); fast_callback(y) }
  stopped <- grr_sample_reference(slow_target, starts, cal, wall)
  stopifnot(stopped$status == "INCONCLUSIVE_BUDGET_LIMITED", !stopped$qualified,
    stopped$callback_evaluations <= 1L, !is.null(stopped$chain_states[[1L]]))
  # Existing/non-existing global seed and nondefault RNG-kind restoration.
  old_kind <- RNGkind(); old_seed <- .Random.seed
  RNGkind("L'Ecuyer-CMRG"); set.seed(114); preserved_kind <- RNGkind(); preserved_seed <- .Random.seed
  one <- ctl; one$chain_ids <- 1L; one$warmup <- 0L; one$samples <- 20L
  zero_warmup <- grr_sample_reference(fixture(), starts, cal, one)
  stopifnot(identical(RNGkind(), preserved_kind), identical(.Random.seed, preserved_seed),
    all(zero_warmup$proposal_factors[, 1L] == zero_warmup$chain_states[[1L]]$initial_proposal_factor),
    zero_warmup$chain_states[[1L]]$adaptation_updates == 0L)
  rm(".Random.seed", envir = .GlobalEnv)
  invisible(grr_sample_reference(fixture(), starts, cal, one))
  stopifnot(!exists(".Random.seed", .GlobalEnv, inherits = FALSE), identical(RNGkind(), preserved_kind))
  do.call(RNGkind, as.list(old_kind)); assign(".Random.seed", old_seed, .GlobalEnv)
  message("GloFAS recovery generated tests passed: calibration/SPD, t density, detailed balance, Normal exact-independence acceptance, AL/nonlinear quadrature, frozen warmup, RNG, metadata progress and all-chain combination.")
})
