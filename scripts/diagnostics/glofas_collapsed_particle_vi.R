# Generated-only building block for a collapsed future-path variational bound.
# No file access, authentic dispatch, parameter optimization or model fitting.
# Requires the pure AL helpers from glofas_innovation_coordinates.R to be loaded.
#
# With eta collecting ALL model parameters and prior variables, write
# Z_G(eta)=integral P_eta(y) L_G(y,eta) dy. The collapsed parameter objective is
# E_q[log pi_H(eta)-log q(eta)+log Z_G(eta)]. A positive, unbiased bootstrap
# particle estimate Zhat gives E(log Zhat)<=log Z_G, not a pointwise bound for
# every realized estimate. Historical parameters must be optimized jointly;
# freezing them or omitting their density ratio is not implemented here.
# A parameter-dependent finite-particle Jensen gap can distort that optimum;
# unbiased evidence estimates alone do not establish parameter accuracy.
#
# Every G_h potential is evaluated on y_<h BEFORE drawing y_h. Multinomial
# resampling preserves the weighted empirical measure in conditional expectation,
# and the normalizer recursion retains the pre-resampling weight sum. This is
# bootstrap SMC on a causal AL law, not a Gaussian replacement for that law.
# Its expected-log objective is consistent with the FIVO/VSMC constructions:
# https://proceedings.mlr.press/v84/naesseth18a/naesseth18a.pdf
# https://proceedings.neurips.cc/paper/2017/file/fa84632d742f2729dc32ce8cb5d49733-Paper.pdf
# No gradient through random resampling is provided or silently discarded.

gcpv_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS collapsed particle VI: ", why), call. = FALSE)
  invisible(TRUE)
}
gcpv_scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
gcpv_integer <- function(x) gcpv_scalar(x) && x == floor(x)
gcpv_flags <- function() list(reference_qualified = FALSE,
  full_posterior_accuracy_qualified = FALSE, production_qualified = FALSE,
  production_launch_authorized = FALSE, publication_authorized = FALSE,
  optimizer_implemented = FALSE, resampling_gradient_implemented = FALSE,
  original_reads = 0L, model_fits = 0L)
gcpv_plain <- function(x, depth = 0L) {
  q <- gcpv_require
  q(depth <= 12L && (is.numeric(x) || is.list(x)) && !is.object(x),
    "plain numeric parameter values required, without callbacks or opaque objects")
  if (is.list(x)) {
    q(length(x) > 0L && (is.null(names(x)) || (!anyDuplicated(names(x)) && all(nzchar(names(x))))),
      "nonempty uniquely named/list parameter values required")
    for (v in x) gcpv_plain(v, depth + 1L)
  } else q(length(x) > 0L && all(is.finite(x)), "finite numeric parameter values required")
  invisible(TRUE)
}
gcpv_logsumexp <- function(x) {
  gcpv_require(is.numeric(x) && length(x) > 0L && !anyNA(x) && all(x < Inf),
    "finite or negative-infinite log weights required")
  a <- max(x)
  if (a == -Inf) return(-Inf)
  a + log(sum(exp(x - a)))
}

gcpv_smc <- function(parameters, location, scale, member_location, member_scale,
    members, horizon, probability = .5, particles = 128L, ess_fraction = .5,
    seed = 2026110501L,
    limits = list(max_horizon = 28L, max_particles = 4096L, max_calls = 1000000L),
    gates = list(min_ess = 2, min_unique_ancestors = 2L)) {
  q <- gcpv_require
  q(all(vapply(c("gic_al_quantile", "gic_al_log_density"), function(n)
    exists(n, envir = environment(gcpv_smc), mode = "function", inherits = TRUE), logical(1L))),
    "pure AL coordinate helpers must be loaded")
  gcpv_plain(parameters)
  q(length(unlist(parameters)) <= 20000L, "bounded generated parameter vector required")
  q(is.list(limits) && setequal(names(limits), c("max_horizon", "max_particles", "max_calls")) &&
    all(vapply(limits, gcpv_integer, logical(1L))) && all(unlist(limits) > 0) &&
    limits$max_horizon <= 28L && limits$max_particles <= 4096L && limits$max_calls <= 1000000L,
    "explicit bounded horizon/particle/callback limits required")
  q(gcpv_integer(horizon) && horizon >= 1L && horizon <= limits$max_horizon &&
    gcpv_integer(particles) && particles >= 1L && particles <= limits$max_particles &&
    gcpv_scalar(ess_fraction) && ess_fraction > 0 && ess_fraction <= 1 &&
    gcpv_integer(seed) && seed > 0 && seed <= .Machine$integer.max &&
    gcpv_scalar(probability) && probability > 0 && probability < 1 && is.function(location),
    "bounded causal AL particle specification required")
  q(is.list(gates) && setequal(names(gates), c("min_ess", "min_unique_ancestors")) &&
    gcpv_scalar(gates$min_ess) && gates$min_ess >= 1 && gates$min_ess <= particles &&
    gcpv_integer(gates$min_unique_ancestors) && gates$min_unique_ancestors >= 1L &&
    gates$min_unique_ancestors <= particles, "prespecified particle-degeneracy gates required")
  if (!is.null(members)) q(is.matrix(members) && is.numeric(members) &&
    identical(dim(members), c(as.integer(horizon), 51L)) && all(is.finite(members)) &&
    is.function(member_location), "all fifty-one ordinary members at every horizon required")
  old_kind <- RNGkind()
  old_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection"); set.seed(as.integer(seed))
  H <- as.integer(horizon); N <- as.integer(particles)
  paths <- matrix(NA_real_, N, H); weights <- rep(1 / N, N)
  ancestors <- seq_len(N); diagnostics <- vector("list", H)
  calls <- 0L; terms <- 0L; completed <- 0L; logZ <- 0; stage <- "START"; error <- NULL
  used <- c(location = 0L, scale = 0L, member_location = 0L, member_scale = 0L)
  value <- function(spec, h, past, role, positive = FALSE) {
    q(calls < limits$max_calls, "declared callback budget exhausted")
    calls <<- calls + 1L; used[[role]] <<- used[[role]] + 1L
    x <- if (is.function(spec)) spec(h, past, parameters) else {
      q(is.numeric(spec) && length(spec) %in% c(1L, H), "scalar, horizon-length or causal scale required")
      spec[if (length(spec) == 1L) 1L else h]
    }
    q(gcpv_scalar(x) && (!positive || x > 0), paste0("valid causal ", role, " required"))
    x
  }
  tryCatch({
    for (h in seq_len(H)) {
      stage <- paste0("WEIGHT_HORIZON_", h)
      if (is.null(members)) {
        # Exact algebraic identity, not a Monte Carlo approximation to one.
        increment <- 0
      } else {
        potential <- vapply(seq_len(N), function(i) {
          past <- if (h == 1L) numeric() else paths[i, seq_len(h - 1L)]
          mu <- value(member_location, h, past, "member_location")
          sigma <- value(member_scale, h, past, "member_scale", TRUE)
          terms <<- terms + 51L
          sum(gic_al_log_density(members[h, ], mu, probability, sigma))
        }, numeric(1L))
        q(all(is.finite(potential)), "finite ordinary-member potentials required")
        candidate <- log(weights) + potential
        increment <- gcpv_logsumexp(candidate)
        q(is.finite(increment), "particle potential normalizer is not representable")
        weights <- exp(candidate - increment)
        weights <- weights / sum(weights)
      }
      logZ <- logZ + increment
      ess <- 1 / sum(weights^2)
      do_resample <- ess < ess_fraction * N
      selected <- seq_len(N)
      if (do_resample) {
        selected <- sample.int(N, N, replace = TRUE, prob = weights)
        paths <- paths[selected, , drop = FALSE]
        ancestors <- ancestors[selected]
        weights <- rep(1 / N, N)
      }
      diagnostics[[h]] <- data.frame(horizon = h, effective_sample_size = ess,
        unique_initial_ancestors = length(unique(ancestors)),
        unique_selected_parents = length(unique(selected)), resampled = do_resample,
        log_normalizer_increment = increment)
      stage <- paste0("PROPAGATE_HORIZON_", h)
      for (i in seq_len(N)) {
        past <- if (h == 1L) numeric() else paths[i, seq_len(h - 1L)]
        mu <- value(location, h, past, "location")
        sigma <- value(scale, h, past, "scale", TRUE)
        # runif is interior under this RNG. Endpoints are rejected by the AL
        # helper rather than clamped or substituted with Gaussian noise.
        paths[i, h] <- gic_al_quantile(stats::runif(1L), probability, mu, sigma)
      }
      completed <- h
    }
  }, error = function(e) { error <<- conditionMessage(e) })
  complete <- is.null(error) && completed == H && all(is.finite(paths))
  records <- diagnostics[!vapply(diagnostics, is.null, logical(1L))]
  records <- if (length(records)) do.call(rbind, records) else data.frame()
  passed <- complete && nrow(records) == H && all(records$effective_sample_size >= gates$min_ess) &&
    all(records$unique_initial_ancestors >= gates$min_unique_ancestors)
  normalizer <- if (complete) exp(logZ) else NA_real_
  normalizer_scale_status <- if (!complete) "partial_no_full_normalizer" else if (normalizer == 0)
    "underflow_log_normalizer_only" else if (!is.finite(normalizer))
    "overflow_log_normalizer_only" else "representable_positive"
  if (!is.finite(normalizer) || normalizer <= 0) normalizer <- NA_real_
  c(list(schema_version = "glofas_generated_collapsed_particle_v1",
    status = if (complete) "COMPLETE_PARTICLE_DIAGNOSTIC_NOT_PRODUCTION" else "FAILED_OR_PARTIAL_NOT_QUALIFIED",
    complete = complete, diagnostic_thresholds_passed = passed, failure = error, failure_stage = if (!complete) stage else NULL,
    parameters = parameters, probability = probability, horizon = H, particles = N, seed = seed,
    paths = paths, weights = weights, initial_ancestor_ids = ancestors, diagnostics = records,
    log_normalizer_estimate = if (complete) logZ else NA_real_,
    normalizer_estimate = normalizer, normalizer_scale_status = normalizer_scale_status,
    partial_log_normalizer = logZ,
    completed_horizons = completed, callback_calls = calls, callback_calls_by_role = used,
    member_factor_evaluations = terms, member_count = if (is.null(members)) 0L else 51L,
    member_weights = if (is.null(members)) numeric() else rep(1, 51L), limits = limits, gates = gates,
    unbiasedness_scope = "In exact arithmetic the normalizer estimate is positive and unbiased under the declared causal model and unbiased multinomial resampling; log estimate is not unbiased. Unrepresentable exponentiated values are NA, not zero or infinity.",
    expected_log_bound = TRUE, realized_log_estimate_is_a_bound = FALSE,
    expected_log_bound_scope = "Expectation over particle randomness at fixed parameters in exact arithmetic; not a guarantee for one numerical estimate.",
    gradient_scope = "No variational or resampling gradient is implemented.",
    family_scope = "generated_AL_only_not_RHS_exAL_MQ_or_authentic_inference"), gcpv_flags())
}

gcpv_joint_objective <- function(parameter_draws, log_historical, log_q,
    smc_args, seeds, parameter_weights = NULL, max_total_calls = 1000000L) {
  q <- gcpv_require
  M <- length(parameter_draws)
  q(is.list(parameter_draws) && M >= 1L && M <= 256L && is.function(log_historical) &&
    is.function(log_q) && is.list(smc_args) && !any(c("parameters", "seed") %in% names(smc_args)) &&
    is.numeric(seeds) && length(seeds) == M && all(is.finite(seeds)) && !anyDuplicated(seeds) &&
    gcpv_integer(max_total_calls) && max_total_calls > 0L && max_total_calls <= 1000000L,
    "bounded uncertain-parameter objective inputs required")
  if (is.null(parameter_weights)) parameter_weights <- rep(1 / M, M)
  q(is.numeric(parameter_weights) && length(parameter_weights) == M &&
    all(is.finite(parameter_weights)) && all(parameter_weights > 0) &&
    abs(sum(parameter_weights) - 1) <= 1e-12, "normalized positive parameter-integration weights required")
  for (p in parameter_draws) gcpv_plain(p)
  components <- rep(NA_real_, M); ratios <- rep(NA_real_, M); records <- vector("list", M)
  used <- 0L; failure <- NULL
  for (j in seq_len(M)) {
    tryCatch({
      lp <- log_historical(parameter_draws[[j]]); lq <- log_q(parameter_draws[[j]])
      q(is.numeric(lp) && length(lp) == 1L && !is.na(lp) && lp < Inf && gcpv_scalar(lq),
        "same-measure historical target and proposal log densities required")
      args <- smc_args
      if (is.null(args$limits)) args$limits <- list(max_horizon = 28L, max_particles = 4096L, max_calls = 1000000L)
      q(used < max_total_calls, "joint parameter/path callback budget exhausted")
      args$limits$max_calls <- min(args$limits$max_calls, max_total_calls - used)
      records[[j]] <- do.call(gcpv_smc, c(list(parameters = parameter_draws[[j]], seed = seeds[j]), args))
      used <- used + records[[j]]$callback_calls
      q(isTRUE(records[[j]]$complete), "partial conditional-particle calculation retained")
      ratios[j] <- lp - lq
      components[j] <- ratios[j] + records[[j]]$log_normalizer_estimate
    }, error = function(e) { failure <<- conditionMessage(e) })
    if (!is.null(failure)) break
  }
  complete <- is.null(failure) && all(!is.na(components))
  passed <- complete && all(is.finite(components)) &&
    all(vapply(records, function(x) isTRUE(x$diagnostic_thresholds_passed), logical(1L)))
  c(list(schema_version = "glofas_generated_collapsed_parameter_objective_v1",
    status = if (complete) "OBJECTIVE_EVALUATED_NOT_OPTIMIZED_OR_QUALIFIED" else "PARTIAL_OBJECTIVE_NOT_QUALIFIED",
    complete = complete, diagnostic_thresholds_passed = passed, failure = failure,
    value = if (complete) sum(parameter_weights * components) else NA_real_,
    parameter_components = components, historical_log_density_ratios = ratios,
    parameter_weights = parameter_weights, conditional_records = records,
    callback_calls = used, max_total_calls = max_total_calls,
    historical_target_factor_count_per_draw = 1L, parameters_frozen = FALSE,
    historical_parameters_optimized = FALSE,
    coordinate_measure = "Caller supplies both densities in the SAME parameter coordinates. A log-scale Jacobian belongs exactly once, in the target or proposal as required; no Jacobian is inserted here.",
    expected_log_bound = TRUE, realized_objective_is_a_bound = FALSE,
    bound_scope = "The lower bound requires exact expectation under q and particle randomness; supplied weighted parameter draws are numerical integration, not a certified integral. A parameter-dependent finite-particle Jensen gap can distort the optimum q even with unbiased normalizers; parameter accuracy needs separate checks as particle count increases.",
    gradient_scope = "No optimizer or resampling gradient; finite realized estimates are not an unbiased gradient oracle."), gcpv_flags())
}

gcpv_finite_difference <- function(objective, point, step = 1e-5,
    objective_scope = "exact_generated_quadrature_oracle") {
  q <- gcpv_require
  q(is.function(objective) && identical(objective_scope, "exact_generated_quadrature_oracle") &&
    is.numeric(point) && length(point) >= 1L && length(point) <= 32L && all(is.finite(point)) &&
    gcpv_scalar(step) && step > 0 && step <= 1e-2, "deterministic exact small-target oracle required")
  gradient <- vapply(seq_along(point), function(j) {
    displacement <- rep(0, length(point)); displacement[j] <- step
    a <- objective(point + displacement); b <- objective(point - displacement)
    q(gcpv_scalar(a) && gcpv_scalar(b), "finite deterministic oracle evaluations required")
    (a - b) / (2 * step)
  }, numeric(1L))
  list(gradient = gradient, evaluations = 2L * length(point), step = step,
    scope = objective_scope, production_optimizer = FALSE,
    resampling_gradient_implemented = FALSE)
}
