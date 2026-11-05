# Exact AL causal innovation coordinates for generated/reference calculations.
# This module evaluates densities and transformations only. It performs no file
# access, fitting, sampling, scoring, resource admission or publication.
#
# For y_h = mu_h(theta,y_<h) + s_h(theta,y_<h) F_p^{-1}(u_h),
# D_u y is lower triangular, with diagonal s_h / f_p(e_h). Consequently
# prod_h f_p(e_h)/s_h * |det D_u y| = 1. In Normal base coordinates,
# u_h = Phi(z_h), the remaining density is prod_h phi(z_h). Dependence on
# unknown theta adds no determinant: (theta,z) -> (theta,y) is block triangular
# with an identity parameter block. Historical parameter density enters once.
# Issued members remain ordinary likelihood factors evaluated at the resulting
# path. An exact coordinate identity is not a qualification of an algorithm.

gic_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS innovation coordinates: ", why), call. = FALSE)
  invisible(TRUE)
}

gic_probability <- function(probability) {
  gic_require(is.numeric(probability) && length(probability) == 1L &&
    is.finite(probability) && probability > 0 && probability < 1,
    "one strictly interior probability required")
  probability
}

gic_expand <- function(x, n, why, finite = TRUE) {
  gic_require(is.numeric(x) && length(x) %in% c(1L, n) &&
    !anyNA(x) && (!finite || all(is.finite(x))), why)
  rep_len(x, n)
}

gic_log1mexp <- function(log_probability) {
  gic_require(is.numeric(log_probability) && !anyNA(log_probability) &&
    all(log_probability <= 0), "nonpositive log probabilities required")
  near_one <- log_probability > -log(2)
  value <- numeric(length(log_probability))
  value[near_one] <- log(-expm1(log_probability[near_one]))
  value[!near_one] <- log1p(-exp(log_probability[!near_one]))
  value
}

gic_al_log_density <- function(y, location = 0, probability = .5, scale = 1) {
  p <- gic_probability(probability)
  gic_require(is.numeric(y) && length(y) > 0L && !anyNA(y),
    "nonempty numeric density arguments required")
  location <- gic_expand(location, length(y), "compatible finite locations required")
  scale <- gic_expand(scale, length(y), "compatible positive scales required")
  gic_require(all(scale > 0), "positive scales required")
  e <- (y - location) / scale
  log(p) + log1p(-p) - log(scale) - e * (p - (e < 0))
}

# Both log tails are retained. In particular, upper-tail calculations do not
# subtract a CDF rounded to one. Infinite responses are allowed at this API.
gic_al_log_tails <- function(y, location = 0, probability = .5, scale = 1) {
  p <- gic_probability(probability)
  gic_require(is.numeric(y) && length(y) > 0L && !anyNA(y),
    "nonempty numeric CDF arguments required")
  location <- gic_expand(location, length(y), "compatible finite locations required")
  scale <- gic_expand(scale, length(y), "compatible positive scales required")
  gic_require(all(scale > 0), "positive scales required")
  e <- (y - location) / scale
  lower <- upper <- numeric(length(e))
  left <- e <= 0
  lower[left] <- log(p) + (1 - p) * e[left]
  upper[left] <- gic_log1mexp(lower[left])
  upper[!left] <- log1p(-p) - p * e[!left]
  lower[!left] <- gic_log1mexp(upper[!left])
  list(lower = lower, upper = upper)
}

gic_al_cdf <- function(y, location = 0, probability = .5, scale = 1,
    lower.tail = TRUE, log.p = FALSE) {
  gic_require(is.logical(lower.tail) && length(lower.tail) == 1L && !is.na(lower.tail) &&
    is.logical(log.p) && length(log.p) == 1L && !is.na(log.p),
    "scalar logical tail and log flags required")
  tails <- gic_al_log_tails(y, location, probability, scale)
  value <- if (lower.tail) tails$lower else tails$upper
  if (log.p) value else exp(value)
}

gic_al_quantile_logs <- function(log_lower, log_upper, probability = .5) {
  p <- gic_probability(probability)
  gic_require(is.numeric(log_lower) && length(log_lower) > 0L &&
    is.numeric(log_upper) && length(log_upper) == length(log_lower) &&
    all(is.finite(log_lower)) && all(is.finite(log_upper)) &&
    all(log_lower <= 0) && all(log_upper <= 0),
    "finite log tails of interior probabilities required")
  # exp(log_lower)+exp(log_upper)=1, evaluated without cancellation.
  larger <- pmax(log_lower, log_upper)
  log_total <- larger + log1p(exp(pmin(log_lower, log_upper) - larger))
  gic_require(all(abs(log_total) <= 1e-12), "inconsistent probability tails")
  left <- log_lower <= log(p)
  value <- numeric(length(left))
  value[left] <- (log_lower[left] - log(p)) / (1 - p)
  value[!left] <- -(log_upper[!left] - log1p(-p)) / p
  gic_require(all(is.finite(value)), "quantile is not representable")
  value
}

gic_al_quantile <- function(u, probability = .5, location = 0, scale = 1) {
  gic_require(is.numeric(u) && length(u) > 0L && all(is.finite(u)) &&
    all(u > 0 & u < 1), "strictly interior uniform coordinates required")
  e <- gic_al_quantile_logs(log(u), log1p(-u), probability)
  location <- gic_expand(location, length(u), "compatible finite locations required")
  scale <- gic_expand(scale, length(u), "compatible positive scales required")
  gic_require(all(scale > 0), "positive scales required")
  value <- location + scale * e
  gic_require(all(is.finite(value)), "response is not representable")
  value
}

# Pointwise helpers for a single-pass retained-DESN adapter. These functions
# require no location callback and do not regenerate any reservoir features.
gic_al_standardized_from_normal <- function(z, probability = .5) {
  gic_require(is.numeric(z) && length(z) > 0L && all(is.finite(z)),
    "finite Normal base coordinates required")
  gic_al_quantile_logs(stats::pnorm(z, log.p = TRUE),
    stats::pnorm(z, lower.tail = FALSE, log.p = TRUE), probability)
}

gic_al_normal_from_standardized <- function(e, probability = .5) {
  gic_require(is.numeric(e) && length(e) > 0L && all(is.finite(e)),
    "finite standardized AL innovations required")
  tails <- gic_al_log_tails(e, probability = probability)
  left <- tails$lower <= log(.5)
  z <- numeric(length(e))
  z[left] <- stats::qnorm(tails$lower[left], log.p = TRUE)
  z[!left] <- stats::qnorm(tails$upper[!left], lower.tail = FALSE, log.p = TRUE)
  gic_require(all(is.finite(z)), "finite Normal inverse coordinates required")
  z
}

gic_causal_value <- function(specification, h, past, parameters, horizon, role) {
  value <- if (is.function(specification)) specification(h, past, parameters) else {
    gic_require(is.numeric(specification) && length(specification) %in% c(1L, horizon),
      paste0(role, " must be scalar, horizon-length, or a causal function"))
    specification[if (length(specification) == 1L) 1L else h]
  }
  gic_require(is.numeric(value) && length(value) == 1L && is.finite(value),
    paste0("one finite ", role, " required at each horizon"))
  if (role == "scale") gic_require(value > 0, "positive scale required at each horizon")
  value
}

gic_al_forward <- function(base, parameters, location, scale, probability = .5,
    base_measure = c("normal", "uniform")) {
  measure <- match.arg(base_measure)
  p <- gic_probability(probability)
  gic_require(is.numeric(base) && is.null(dim(base)) && length(base) > 0L &&
    all(is.finite(base)), "one finite coordinate vector required")
  gic_require(is.function(location), "causal location(h,past,parameters) required")
  if (measure == "uniform") {
    gic_require(all(base > 0 & base < 1), "uniform coordinates must be strictly interior")
    lower <- log(base); upper <- log1p(-base)
    log_base <- rep(0, length(base))
  } else {
    lower <- stats::pnorm(base, log.p = TRUE)
    upper <- stats::pnorm(base, lower.tail = FALSE, log.p = TRUE)
    log_base <- stats::dnorm(base, log = TRUE)
  }
  e <- gic_al_quantile_logs(lower, upper, p)
  n <- length(base)
  path <- locations <- scales <- numeric(n)
  for (h in seq_len(n)) {
    # Only the h-1 earlier responses are passed; future responses cannot enter
    # through the path argument. Callback purity is the caller's obligation.
    past <- if (h == 1L) numeric() else path[seq_len(h - 1L)]
    locations[h] <- gic_causal_value(location, h, past, parameters, n, "location")
    scales[h] <- gic_causal_value(scale, h, past, parameters, n, "scale")
    path[h] <- locations[h] + scales[h] * e[h]
    gic_require(is.finite(path[h]), "finite generated path required")
  }
  log_standardized <- gic_al_log_density(e, probability = p)
  log_path_terms <- log_standardized - log(scales)
  log_jacobian_terms <- log(scales) - log_standardized + log_base
  list(path = path, base = base, locations = locations, scales = scales,
    standardized_innovations = e, probability = p, base_measure = measure,
    log_path_density = sum(log_path_terms), log_base_density = sum(log_base),
    log_abs_jacobian = sum(log_jacobian_terms),
    log_abs_jacobian_terms = log_jacobian_terms,
    identity_residual = sum(log_path_terms) + sum(log_jacobian_terms) - sum(log_base),
    original_reads = 0L, production_qualified = FALSE)
}

gic_al_inverse <- function(path, parameters, location, scale, probability = .5,
    base_measure = c("normal", "uniform")) {
  measure <- match.arg(base_measure)
  p <- gic_probability(probability)
  gic_require(is.numeric(path) && is.null(dim(path)) && length(path) > 0L &&
    all(is.finite(path)) && is.function(location), "finite path and causal location required")
  n <- length(path)
  locations <- scales <- numeric(n)
  for (h in seq_len(n)) {
    past <- if (h == 1L) numeric() else path[seq_len(h - 1L)]
    locations[h] <- gic_causal_value(location, h, past, parameters, n, "location")
    scales[h] <- gic_causal_value(scale, h, past, parameters, n, "scale")
  }
  tails <- gic_al_log_tails(path, locations, p, scales)
  if (measure == "uniform") {
    base <- exp(tails$lower)
    gic_require(all(base > 0 & base < 1),
      "uniform inverse is not representable; use Normal base log tails")
  } else {
    base <- gic_al_normal_from_standardized((path - locations) / scales, p)
  }
  gic_require(all(is.finite(base)), "finite inverse coordinates required")
  forward <- gic_al_forward(base, parameters, location, scale, p, measure)
  forward$inverse_path_residual <- max(abs(forward$path - path))
  forward
}

# Members are H x 51, without powers, weights, averaging or latent integration.
# NULL explicitly requests the no-member mathematical identity. No other member
# count is silently accepted. Unlike the generative location, the conditioning
# likelihood's location/scale may depend on the entire resulting path.
gic_al_member_target <- function(base, parameters, location, scale, probability,
    members, member_location, member_scale, log_historical,
    base_measure = c("normal", "uniform")) {
  measure <- match.arg(base_measure)
  transformed <- gic_al_forward(base, parameters, location, scale, probability, measure)
  n <- length(base)
  historical <- if (is.function(log_historical)) log_historical(parameters) else log_historical
  gic_require(is.numeric(historical) && length(historical) == 1L &&
    !is.na(historical) && historical < Inf, "one historical log density, possibly -Inf, required")
  if (is.null(members)) {
    factors <- matrix(numeric(), nrow = n, ncol = 0L)
  } else {
    gic_require(is.matrix(members) && is.numeric(members) &&
      identical(dim(members), c(n, 51L)) && all(is.finite(members)),
      "all fifty-one finite members at every horizon required")
    gic_require(is.function(member_location), "member_location(h,path,parameters) required")
    factors <- matrix(NA_real_, nrow = n, ncol = 51L)
    for (h in seq_len(n)) {
      mu <- gic_causal_value(member_location, h, transformed$path, parameters, n, "location")
      s <- gic_causal_value(member_scale, h, transformed$path, parameters, n, "scale")
      factors[h, ] <- gic_al_log_density(members[h, ], mu, probability, s)
    }
  }
  member_sum <- sum(factors)
  list(log_target = historical + member_sum + transformed$log_base_density,
    log_historical = historical, log_member_likelihood = member_sum,
    member_log_factors = factors, member_count = ncol(factors),
    member_factor_count = length(factors), member_weights = rep(1, ncol(factors)),
    transformed = transformed, family = "AL", path_convention = "single_level_path",
    original_reads = 0L, production_qualified = FALSE)
}

# One distinct future path per probability level. The historical MQ target
# (including the adjacent-coefficient prior) enters ONCE. There is no common-Y
# product normalization; the product of separate conditional path laws is
# normalized on its product path space. This evaluates that target, not MQ VB.
gic_al_mq_target <- function(base, parameters, locations, scales, probabilities,
    members, member_locations, member_scales, log_historical,
    base_measure = c("normal", "uniform")) {
  measure <- match.arg(base_measure)
  gic_require(is.matrix(base) && is.numeric(base) && all(dim(base) > 0L) &&
    all(is.finite(base)), "horizon-by-level coordinate matrix required")
  k <- ncol(base)
  gic_require(is.numeric(probabilities) && length(probabilities) == k &&
    all(is.finite(probabilities)) && all(probabilities > 0 & probabilities < 1) &&
    (k == 1L || all(diff(probabilities) > 0)), "ordered interior probability levels required")
  for (x in list(locations, scales, members, member_locations, member_scales))
    gic_require(is.list(x) && length(x) == k, "one explicit specification per level required")
  historical <- if (is.function(log_historical)) log_historical(parameters) else log_historical
  gic_require(is.numeric(historical) && length(historical) == 1L &&
    !is.na(historical) && historical < Inf, "one historical MQ log density required")
  levels <- lapply(seq_len(k), function(j) gic_al_member_target(base[, j], parameters,
    locations[[j]], scales[[j]], probabilities[j], members[[j]],
    member_locations[[j]], member_scales[[j]], 0, measure))
  paths <- vapply(levels, function(x) x$transformed$path, numeric(nrow(base)))
  dim(paths) <- dim(base)
  list(log_target = historical + sum(vapply(levels, function(x) x$log_target, numeric(1L))),
    log_historical = historical, paths = paths, levels = levels,
    path_convention = "separate_path_per_probability", historical_factor_count = 1L,
    log_abs_jacobian = sum(vapply(levels, function(x) x$transformed$log_abs_jacobian, numeric(1L))),
    log_path_density = sum(vapply(levels, function(x) x$transformed$log_path_density, numeric(1L))),
    log_base_density = sum(vapply(levels, function(x) x$transformed$log_base_density, numeric(1L))),
    original_reads = 0L, production_qualified = FALSE)
}
