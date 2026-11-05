# Generated guided SMC on the original causal AL future law.
# G_h depends on Y_<h: weight G_h, optionally resample, propose Y_h, then
# retain the complete f(Y_h|past)/q_h(Y_h|past) correction. There is NO
# resampling between this correction and the next G_{h+1} contribution.
# Terminal Y_H uses its normalized prior transition and integrates to one.
#
# Generic callbacks are experimental, not authenticated normalized proposals.
# The narrow affine H2 adapter below constructs an independently checked
# full-real-line proposal; callback flags alone are not mathematical evidence.
# No parameters are fitted/frozen here, and there is no original-data reader.
# General SMC importance/normalizer identity:
# https://proceedings.mlr.press/v84/naesseth18a/naesseth18a.pdf

gpg_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS guided collapsed particle: ", why), call. = FALSE)
  invisible(TRUE)
}
gpg_smc <- function(parameters, location, scale, member_location, member_scale,
    members, horizon, probability = .5, particles = 128L, ess_fraction = .5,
    seed = 2026110501L, guide = NULL,
    limits = list(max_horizon = 28L, max_particles = 4096L, max_calls = 1000000L),
    gates = list(min_ess = 2, min_unique_ancestors = 2L)) {
  q <- gpg_require
  q(all(vapply(c("gcpv_plain", "gcpv_scalar", "gcpv_integer", "gcpv_logsumexp",
    "gcpv_flags", "gic_al_quantile", "gic_al_log_density"), function(n)
    exists(n, envir = environment(gpg_smc), mode = "function", inherits = TRUE), logical(1L))),
    "load pure generated particle and AL helpers first")
  gcpv_plain(parameters)
  q(length(unlist(parameters)) <= 20000L && is.function(location) &&
    (is.null(guide) || is.function(guide)), "bounded generated parameters and causal callbacks required")
  q(is.list(limits) && setequal(names(limits), c("max_horizon", "max_particles", "max_calls")) &&
    length(limits) == 3L && all(vapply(limits, gcpv_integer, logical(1L))) &&
    all(unlist(limits) > 0) && limits$max_horizon <= 28L && limits$max_particles <= 4096L &&
    limits$max_calls <= 1000000L, "exact bounded horizon/particle/callback controls required")
  q(gcpv_integer(horizon) && horizon >= 1L && horizon <= limits$max_horizon &&
    gcpv_integer(particles) && particles >= 1L && particles <= limits$max_particles &&
    gcpv_scalar(probability) && probability > 0 && probability < 1 &&
    gcpv_scalar(ess_fraction) && ess_fraction > 0 && ess_fraction <= 1 &&
    gcpv_integer(seed) && seed > 0 && seed <= .Machine$integer.max,
    "bounded causal AL particle specification required")
  q(is.list(gates) && setequal(names(gates), c("min_ess", "min_unique_ancestors")) &&
    length(gates) == 2L && gcpv_scalar(gates$min_ess) && gates$min_ess >= 1 &&
    gates$min_ess <= particles && gcpv_integer(gates$min_unique_ancestors) &&
    gates$min_unique_ancestors >= 1 && gates$min_unique_ancestors <= particles,
    "exact prespecified degeneracy gates required")
  if (!is.null(members)) q(is.matrix(members) && is.numeric(members) &&
    identical(dim(members), c(as.integer(horizon), 51L)) && all(is.finite(members)) &&
    is.function(member_location), "all fifty-one ordinary member factors required")
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
  log_weights <- rep(-log(N), N)
  # Probability-scale weights may underflow after f/q and revive under the
  # next G contribution. Preserve their finite logs through this cancellation.
  # NULL-guide arithmetic is retained exactly for bootstrap regression checks.
  carry_log_weights <- !is.null(guide) && !is.null(members)
  ancestors <- seq_len(N); diagnostics <- vector("list", H)
  calls <- terms <- completed <- 0L; logZ <- 0; stage <- "START"; failure <- NULL
  used <- c(location = 0L, scale = 0L, member_location = 0L, member_scale = 0L,
    guide_factory = 0L, proposal_draw = 0L, proposal_log_density = 0L)
  invoke <- function(fn, ..., role) {
    q(calls < limits$max_calls, "declared callback budget exhausted")
    calls <<- calls + 1L; used[[role]] <<- used[[role]] + 1L
    before <- get(".Random.seed", .GlobalEnv)
    out <- fn(...)
    q(identical(before, get(".Random.seed", .GlobalEnv)), "callbacks must preserve the kernel RNG stream")
    out
  }
  value <- function(spec, h, past, role, positive = FALSE) {
    x <- if (is.function(spec)) invoke(spec, h, past, parameters, role = role) else {
      q(calls < limits$max_calls, "declared callback budget exhausted")
      calls <<- calls + 1L; used[[role]] <<- used[[role]] + 1L
      q(is.numeric(spec) && length(spec) %in% c(1L, H), "scalar or horizon-length causal value required")
      spec[if (length(spec) == 1L) 1L else h]
    }
    q(gcpv_scalar(x) && (!positive || x > 0), paste0("finite causal ", role, " required"))
    x
  }
  normalize <- function(log_increment) {
    candidate <- (if (carry_log_weights) log_weights else log(weights)) + log_increment
    increment <- gcpv_logsumexp(candidate)
    q(is.finite(increment), "importance normalizer is not representable")
    log_weights <<- candidate - increment
    weights <<- exp(log_weights)
    weights <<- weights / sum(weights)
    logZ <<- logZ + increment
    increment
  }
  tryCatch({
    for (h in seq_len(H)) {
      stage <- paste0("MEMBER_WEIGHT_HORIZON_", h)
      member_increment <- 0
      if (!is.null(members)) {
        potential <- vapply(seq_len(N), function(i) {
          past <- if (h == 1L) numeric() else paths[i, seq_len(h - 1L)]
          mu <- value(member_location, h, past, "member_location")
          sigma <- value(member_scale, h, past, "member_scale", TRUE)
          terms <<- terms + 51L
          sum(gic_al_log_density(members[h, ], mu, probability, sigma))
        }, numeric(1L))
        q(all(is.finite(potential)), "finite ordinary-member potentials required")
        member_increment <- normalize(potential)
      }
      member_ess <- 1 / sum(weights^2)
      selected <- seq_len(N)
      do_resample <- member_ess < ess_fraction * N
      if (do_resample) {
        selected <- sample.int(N, N, replace = TRUE, prob = weights)
        paths <- paths[selected, , drop = FALSE]; ancestors <- ancestors[selected]
        weights <- rep(1 / N, N)
        log_weights <- rep(-log(N), N)
      }
      stage <- paste0("PROPOSE_AND_CORRECT_HORIZON_", h)
      correction <- numeric(N); guided <- 0L
      for (i in seq_len(N)) {
        past <- if (h == 1L) numeric() else paths[i, seq_len(h - 1L)]
        mu <- value(location, h, past, "location")
        sigma <- value(scale, h, past, "scale", TRUE)
        # Terminal prior and the no-member identity do not need a guide.
        proposal <- if (h == H || is.null(members) || is.null(guide)) NULL else
          invoke(guide, h = h, past = past, parameters = parameters,
            prior_location = mu, prior_scale = sigma, probability = probability,
            role = "guide_factory")
        u <- stats::runif(1L)
        if (is.null(proposal)) paths[i, h] <- gic_al_quantile(u, probability, mu, sigma) else {
          # These flags describe scope, not proof that an arbitrary q is normalized.
          q(is.list(proposal) && is.function(proposal$draw) && is.function(proposal$log_density) &&
            identical(proposal$proposal_only, TRUE) && identical(proposal$production_qualified, FALSE),
            "experimental proposal envelope required; flags do not certify its density")
          y <- invoke(proposal$draw, u, role = "proposal_draw")
          q(gcpv_scalar(y), "finite guided inverse-CDF sample required")
          logq <- invoke(proposal$log_density, y, role = "proposal_log_density")
          logf <- gic_al_log_density(y, mu, probability, sigma)
          q(gcpv_scalar(logq) && gcpv_scalar(logf), "finite full prior/proposal log densities required")
          paths[i, h] <- y; correction[i] <- logf - logq; guided <- guided + 1L
        }
      }
      correction_increment <- if (guided > 0L) normalize(correction) else 0
      # CRITICAL: do not resample this corrected cloud before G_{h+1}.
      diagnostics[[h]] <- data.frame(horizon = h, effective_sample_size = member_ess,
        unique_initial_ancestors = length(unique(ancestors)),
        unique_selected_parents = length(unique(selected)), resampled = do_resample,
        log_member_increment = member_increment,
        log_proposal_correction_increment = correction_increment,
        log_normalizer_increment = member_increment + correction_increment,
        post_correction_ESS = 1 / sum(weights^2), guided_particles = guided,
        resampled_after_correction = FALSE)
      completed <- h
    }
  }, error = function(e) { failure <<- conditionMessage(e) })
  complete <- is.null(failure) && completed == H && all(is.finite(paths))
  records <- diagnostics[!vapply(diagnostics, is.null, logical(1L))]
  records <- if (length(records)) do.call(rbind, records) else data.frame()
  passed <- complete && nrow(records) == H && all(records$effective_sample_size >= gates$min_ess) &&
    all(records$unique_initial_ancestors >= gates$min_unique_ancestors)
  normalizer <- if (complete) exp(logZ) else NA_real_
  representation <- if (!complete) "partial_no_full_normalizer" else if (normalizer == 0)
    "underflow_log_normalizer_only" else if (!is.finite(normalizer))
    "overflow_log_normalizer_only" else "representable_positive"
  if (!is.finite(normalizer) || normalizer <= 0) normalizer <- NA_real_
  c(list(schema_version = "glofas_generated_guided_collapsed_particle_v1",
    status = if (complete) "COMPLETE_EXPERIMENTAL_GENERATED_DIAGNOSTIC" else "FAILED_OR_PARTIAL_NOT_QUALIFIED",
    complete = complete, diagnostic_thresholds_passed = passed, failure = failure,
    failure_stage = if (complete) NULL else stage,
    paths = paths, weights = weights, log_weights = log_weights,
    initial_ancestor_ids = ancestors, diagnostics = records,
    log_normalizer_estimate = if (complete) logZ else NA_real_, normalizer_estimate = normalizer,
    normalizer_scale_status = representation, partial_log_normalizer = logZ,
    completed_horizons = completed, callback_calls = calls, callback_calls_by_role = used,
    member_factor_evaluations = terms, member_count = if (is.null(members)) 0L else 51L,
    member_weights = if (is.null(members)) numeric() else rep(1,51L),
    parameters = parameters, horizon = H, particles = N, probability = probability, seed = seed,
    limits = limits, gates = gates, terminal_prior_proposal = TRUE,
    no_resampling_between_correction_and_next_member = TRUE,
    generic_proposal_normalization_authenticated = FALSE,
    unbiasedness_scope = "Exact-arithmetic positive unbiased normalizer requires normalized full-support proposals and the complete f/q correction; arbitrary callback flags do not certify these conditions.",
    expected_log_bound = TRUE, realized_log_estimate_is_a_bound = FALSE,
    expected_log_bound_scope = "Expectation at fixed parameters under valid proposals; not a pointwise numerical bound or full-parameter accuracy claim.",
    family_scope = "generated_AL_only_no_native_DESN_RHS_exAL_MQ_qualification"), gcpv_flags())
}

# Verified generated affine H2 adapter: q1(Y1) is proportional to the SAME
# normalized Y1 transition times ALL51 G2 factors. Then f/q=I/G2 and the
# correction and next G2 contribution cancel particle by particle. The H2
# normalizer equals G1*I for every particle count, in exact arithmetic.
gpg_affine_h2 <- function(binding, eta, particles = 16L, ess_fraction = .5,
    seed = 2026110501L, limits = list(max_horizon = 2L, max_particles = 4096L, max_calls = 1000000L),
    gates = list(min_ess = 1, min_unique_ancestors = 1L)) {
  q <- gpg_require
  q(all(vapply(c("gafsp_assert", "gaag_build", "gaag_as_guide"), function(n)
    exists(n, envir = environment(gpg_affine_h2), mode = "function", inherits = TRUE), logical(1L))),
    "load sealed generated binding and exact affine guide first")
  gafsp_assert(binding)
  q(binding$fixture$horizon == 2L, "verified generated affine H2 binding only")
  spec <- binding$spec; f <- binding$fixture
  decoded <- binding$private$gcat_decode(eta, spec)
  parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  guide <- NULL; logI <- 0
  if (!is.null(f$members)) {
    muY1 <- binding$callbacks$location(1L, numeric(), parameters)
    offset <- sum(f$reference_features[2L, ] * parameters$coefficients[spec$blocks$beta$index]) +
      sum(f$discrepancy_features[2L, ] * parameters$coefficients[spec$blocks$alpha$index]) + f$known_baseline[2L]
    proposal <- gaag_build(mu = muY1, sigma_y = unname(decoded$sigma["Y"]),
      members = f$members[2L, ], offset = offset,
      lag = f$reference_lag + f$discrepancy_lag, sigma_g = unname(decoded$sigma["G"]),
      probability = spec$probability)
    envelope <- gaag_as_guide(proposal); logI <- proposal$log_normalizer
    guide <- function(h, past, parameters, prior_location, prior_scale, probability) {
      q(h == 1L && length(past) == 0L && identical(prior_location, muY1) &&
        identical(prior_scale, unname(decoded$sigma["Y"])) && identical(probability, spec$probability),
        "affine guide prior binding changed")
      envelope
    }
  }
  out <- gpg_smc(parameters, binding$callbacks$location,
    function(h,past,parameters) unname(parameters$sigma["Y"]),
    binding$callbacks$member_location, function(h,past,parameters) unname(parameters$sigma["G"]),
    f$members, 2L, spec$probability, particles, ess_fraction, seed, guide, limits, gates)
  out$guide_scope <- "Verified generated affine H2 full-support normalized guide; no native/application admission"
  out$affine_guide_log_integral <- logI
  out$source_sha256 <- binding$source_sha256
  out$full_parameter_dimensions <- spec$dimension
  out$original_parameter_values_changed <- FALSE
  out
}
