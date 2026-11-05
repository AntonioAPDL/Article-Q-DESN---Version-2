# Pure marginal-AL historical target and exact diagonal-Gaussian ELBO.
# No file access, production dispatch, feature rebuilding or publication.
# All supplied coefficient, source-scale and NS auxiliary coordinates remain
# random. AL mixture variables are integrated out, not fixed at VB moments.
gcat_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS collapsed AL target: ", why), call. = FALSE)
}
gcat_positive <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0
gcat_spec <- function(p, blocks, probability, scale_prior) {
  q <- gcat_require
  q(is.numeric(p) && length(p) == 1L && is.finite(p) && p == floor(p) && p >= 4 && p <= 4096 &&
    gcat_positive(probability) && probability < 1, "bounded coefficient dimension and probability required")
  q(is.list(blocks) && identical(names(blocks), c("beta", "alpha")) &&
    is.list(scale_prior) && identical(names(scale_prior), c("Y", "G")), "two explicit coefficient/source blocks required")
  for (s in c("Y", "G")) q(is.numeric(scale_prior[[s]]) &&
    identical(names(scale_prior[[s]]), c("shape", "rate")) &&
    all(is.finite(scale_prior[[s]])) && all(scale_prior[[s]] > 0), "proper explicit source-scale priors required")
  coords <- paste0("coefficient_", seq_len(p))
  positive <- integer(); scales <- c(Y = p + 1L, G = p + 2L)
  coords <- c(coords, "log_sigma_Y", "log_sigma_G"); positive <- unname(scales)
  used <- integer()
  for (name in names(blocks)) {
    b <- blocks[[name]]
    q(is.list(b) && setequal(names(b), c("index", "intercept_index", "tau0", "intercept_prec",
      "slab_shape", "slab_rate", "zeta2_fixed")) && !anyDuplicated(names(b)), "complete explicit NS block required")
    q(is.numeric(b$index) && length(b$index) >= 2L && !anyDuplicated(b$index) &&
      all(is.finite(b$index)) && all(b$index == floor(b$index)) && all(b$index %in% seq_len(p)) &&
      length(b$intercept_index) == 1L && b$intercept_index %in% b$index &&
      all(vapply(b[c("tau0", "intercept_prec", "slab_shape", "slab_rate")], gcat_positive, logical(1L))) &&
      (is.null(b$zeta2_fixed) || gcat_positive(b$zeta2_fixed)), "proper NS coordinates and hyperparameters required")
    b$penalized <- setdiff(b$index, b$intercept_index)
    add <- function(prefix, count) {
      ix <- length(coords) + seq_len(count)
      coords <<- c(coords, paste0(prefix, "_", name, "_", seq_len(count)))
      positive <<- c(positive, ix); ix
    }
    b$tau <- add("log_tau2", 1L); b$xi <- add("log_xi", 1L)
    b$lambda <- add("log_lambda2", length(b$penalized)); b$nu <- add("log_nu", length(b$penalized))
    b$slab <- if (is.null(b$zeta2_fixed)) add("log_zeta2", 1L) else integer()
    blocks[[name]] <- b; used <- c(used, b$index)
  }
  q(identical(sort(as.integer(used)), seq_len(as.integer(p))) && !anyDuplicated(used),
    "coefficient blocks must partition all coefficients exactly once")
  list(schema_version = "glofas_generated_collapsed_AL_target_v1", p = as.integer(p),
    dimension = length(coords), coordinate_names = coords, positive = positive, scales = scales,
    blocks = blocks, probability = probability, scale_prior = scale_prior,
    prior = "NS_product_not_normalized_PV_conditional", coordinate_measure = "coefficients_and_log_positive_parameters",
    historical_auxiliaries = "AL_mixture_variables_integrated_out_exactly",
    optimizer_qualified = FALSE, production_qualified = FALSE)
}
gcat_vector <- function(x, spec) {
  gcat_require(is.numeric(x) && length(x) == spec$dimension && all(is.finite(x)) &&
    (is.null(names(x)) || identical(names(x), spec$coordinate_names)), "all ordered finite parameter coordinates required")
  invisible(TRUE)
}
gcat_decode <- function(x, spec) {
  gcat_vector(x, spec)
  v <- exp(x[spec$positive])
  gcat_require(all(is.finite(v)) && all(v > 0), "positive coordinates are not representable; no clipping permitted")
  list(coefficients = x[seq_len(spec$p)], sigma = setNames(exp(x[spec$scales]), names(spec$scales)),
    positive = setNames(v, spec$coordinate_names[spec$positive]),
    log_jacobian = sum(x[spec$positive]))
}
gcat_bind_historical <- function(spec, H, z, source, weight = rep(1, length(z))) {
  q <- gcat_require
  q(is.matrix(H) && is.numeric(H) && ncol(H) == spec$p && nrow(H) >= 2L &&
    length(H) <= 1e8 && all(is.finite(H)) && is.numeric(z) && length(z) == nrow(H) && all(is.finite(z)) &&
    is.character(source) && length(source) == length(z) && setequal(unique(source), c("Y", "G")) &&
    is.numeric(weight) && length(weight) == length(z) && all(is.finite(weight)) && all(weight == 1),
    "finite aligned historical Y/G rows with unit factors required")
  # These structural zeros distinguish the source-specific regression equations.
  q(all(H[source == "Y", spec$blocks$alpha$index, drop = FALSE] == 0),
    "historical Y must not include discrepancy coefficients")
  list(schema_version = "glofas_generated_collapsed_AL_binding_v1", spec = spec,
    H = H, H_squared = H^2, z = z, source = source, weight = weight,
    input_scope = "caller_supplied_arrays_no_payload_read_or_source_admission",
    production_qualified = FALSE)
}

# Independent point-density calculation in physical/log coordinates.
gcat_log_prior <- function(x, spec, measure = "transformed") {
  gcat_vector(x, spec); d <- gcat_decode(x, spec)
  gcat_require(identical(measure, "transformed") || identical(measure, "physical"), "explicit density measure required")
  log_ig <- function(log_x, a, log_b) a * log_b - lgamma(a) - (a + 1) * log_x - exp(log_b - log_x)
  normal <- function(beta, log_variance) -.5 * (log(2 * pi) + log_variance + beta^2 * exp(-log_variance))
  value <- 0
  for (s in c("Y", "G")) {
    pr <- spec$scale_prior[[s]]
    value <- value + log_ig(x[spec$scales[s]], pr["shape"], log(pr["rate"]))
  }
  for (b in spec$blocks) {
    beta <- x[b$penalized]; t <- x[b$tau]; l <- x[b$lambda]; nu <- x[b$nu]; xi <- x[b$xi]
    slab <- if (length(b$slab)) x[b$slab] else log(b$zeta2_fixed)
    value <- value + sum(normal(beta, t + l)) + sum(normal(beta, slab)) +
      normal(x[b$intercept_index], -log(b$intercept_prec)) +
      log_ig(t, .5, -xi) + log_ig(xi, .5, -2 * log(b$tau0)) +
      sum(log_ig(l, .5, -nu)) + sum(log_ig(nu, .5, 0))
    if (length(b$slab)) value <- value + log_ig(slab, b$slab_shape, log(b$slab_rate))
  }
  value <- value + if (measure == "transformed") d$log_jacobian else 0
  gcat_require(is.finite(value), "nonfinite full prior density; no replacement or clipping permitted")
  as.numeric(value)
}
gcat_log_historical <- function(x, binding) {
  spec <- binding$spec; d <- gcat_decode(x, spec)
  sigma <- d$sigma[binding$source]
  residual <- binding$z - as.numeric(binding$H %*% d$coefficients)
  p <- spec$probability
  likelihood <- sum(log(p) + log1p(-p) - log(sigma) - residual * (p - (residual < 0)) / sigma)
  value <- likelihood + gcat_log_prior(x, spec, "transformed")
  gcat_require(is.finite(value), "nonfinite historical marginal target")
  value
}

# Exact expectation and analytic derivatives for q(x)=prod Normal(m_j,s_j^2).
# The value INCLUDES q entropy; it is not added again by the outer optimizer.
gcat_historical_elbo <- function(mean, log_sd, binding, factor = NULL) {
  spec <- binding$spec; gcat_vector(mean, spec); gcat_vector(log_sd, spec)
  gcat_require(is.null(factor), "this analytic callback requires identity factor, not a silently diagonalized covariance")
  variance <- exp(2 * log_sd)
  gcat_require(all(is.finite(variance)) && all(variance > 0), "representable positive variational variances required")
  value <- 0; gm <- gv <- numeric(spec$dimension)
  add_linear <- function(index, coefficient) {
    value <<- value + sum(coefficient * mean[index]); gm[index] <<- gm[index] + coefficient
  }
  add_ig <- function(index, a, log_b = 0, aux = integer()) {
    # Rate is exp(log_b), or exp(-x_aux) for the NS auxiliary hierarchy.
    if (length(aux)) {
      e <- exp(-mean[aux] - mean[index] + .5 * (variance[aux] + variance[index]))
      value <<- value + sum(-a * mean[aux] - lgamma(a) - (a + 1) * mean[index] - e)
      gm[aux] <<- gm[aux] - a + e; gv[aux] <<- gv[aux] - .5 * e
    } else {
      e <- exp(log_b - mean[index] + .5 * variance[index])
      value <<- value + sum(a * log_b - lgamma(a) - (a + 1) * mean[index] - e)
    }
    gm[index] <<- gm[index] - (a + 1) + e; gv[index] <<- gv[index] - .5 * e
  }
  add_normal <- function(index, logs = integer(), fixed_log_variance = 0) {
    r <- length(index)
    # Each slope has its own lambda; the scalar tau/slab is shared across r.
    if (length(logs)) {
      if (is.matrix(logs)) {
        lm <- colSums(matrix(mean[logs], nrow = nrow(logs)))
        lv <- colSums(matrix(variance[logs], nrow = nrow(logs)))
      } else { lm <- rep(mean[logs], r); lv <- rep(variance[logs], r) }
    } else { lm <- rep(fixed_log_variance, r); lv <- numeric(r) }
    e <- exp(-lm + .5 * lv); second <- variance[index] + mean[index]^2
    value <<- value - .5 * sum(log(2 * pi) + lm + second * e)
    gm[index] <<- gm[index] - mean[index] * e; gv[index] <<- gv[index] - .5 * e
    if (length(logs)) {
      dm <- -.5 + .5 * second * e; dv <- -.25 * second * e
      # Sum repeated global/slab coordinates; indexed assignment alone would
      # discard all but one slope's contribution.
      ix <- if (is.matrix(logs)) as.integer(logs) else rep(logs, r)
      mult <- if (is.matrix(logs)) nrow(logs) else 1L
      for (j in unique(ix)) {
        pos <- which(ix == j); columns <- ceiling(pos / mult)
        gm[j] <<- gm[j] + sum(dm[columns]); gv[j] <<- gv[j] + sum(dv[columns])
      }
    }
  }
  for (s in c("Y", "G")) {
    ix <- which(binding$source == s); si <- spec$scales[s]; H <- binding$H[ix, , drop = FALSE]
    H2 <- binding$H_squared[ix, , drop = FALSE]
    location <- as.numeric(H %*% mean[seq_len(spec$p)])
    v <- as.numeric(H2 %*% variance[seq_len(spec$p)])
    gcat_require(all(v > 0), "nonzero Gaussian readout variance required for analytic AL derivatives")
    sd <- sqrt(v); residual <- binding$z[ix] - location; a <- residual / sd
    phi <- stats::dnorm(a); tail <- stats::pnorm(a, lower.tail = FALSE)
    loss <- sd * phi + residual * (spec$probability - tail)
    e <- exp(-mean[si] + .5 * variance[si])
    value <- value + length(ix) * (log(spec$probability) + log1p(-spec$probability) - mean[si]) - e * sum(loss)
    ci <- seq_len(spec$p)
    gm[ci] <- gm[ci] + as.numeric(crossprod(H, e * (spec$probability - tail)))
    gv[ci] <- gv[ci] - as.numeric(crossprod(H2, e * phi / (2 * sd)))
    gm[si] <- gm[si] - length(ix) + e * sum(loss)
    gv[si] <- gv[si] - .5 * e * sum(loss)
    pr <- spec$scale_prior[[s]]; add_ig(si, pr["shape"], log(pr["rate"]))
  }
  for (b in spec$blocks) {
    add_normal(b$intercept_index, fixed_log_variance = -log(b$intercept_prec))
    add_normal(b$penalized, rbind(rep(b$tau, length(b$penalized)), b$lambda))
    if (length(b$slab)) add_normal(b$penalized, b$slab) else
      add_normal(b$penalized, fixed_log_variance = log(b$zeta2_fixed))
    add_ig(b$tau, .5, aux = b$xi); add_ig(b$xi, .5, -2 * log(b$tau0))
    add_ig(b$lambda, .5, aux = b$nu); add_ig(b$nu, .5)
    if (length(b$slab)) add_ig(b$slab, b$slab_shape, log(b$slab_rate))
  }
  add_linear(spec$positive, 1) # parameter transformation Jacobian exactly once
  value <- value + sum(log_sd) + .5 * spec$dimension * (1 + log(2 * pi))
  gradient_log_sd <- 2 * variance * gv + 1 # analytic entropy derivative once
  gcat_require(is.finite(value) && all(is.finite(c(gm, gradient_log_sd))), "nonfinite exact historical ELBO/gradient")
  list(value = value, gradient_mean = gm, gradient_log_sd = gradient_log_sd,
    entropy_included = TRUE, analytic_historical = TRUE,
    family = "diagonal_Gaussian_all_transformed_parameters", historical_target = "marginal_AL_full_NS_product",
    jacobian_count = 1L, all_parameter_dimensions = spec$dimension, production_qualified = FALSE)
}

# Conditional particle evidence for the SAME source-specific AL target.
# Supplied location callbacks consume the preceding causal Y path and the
# decoded coefficients/scales; they do not receive the current Y_h. This
# interface is not authentication of a callback's captured environment or of
# actual input provenance. Native continuation still needs separate admission.
gcat_make_evidence <- function(spec, members, location, member_location, horizon,
    particles = 64L, ess_fraction = .5,
    limits = list(max_horizon = 28L, max_particles = 4096L, max_calls = 1000000L),
    gates = list(min_ess = 2, min_unique_ancestors = 2L)) {
  q <- gcat_require
  q(is.numeric(horizon) && length(horizon) == 1L && horizon == floor(horizon) &&
    horizon >= 1 && horizon <= 28 && is.function(location) && is.function(member_location),
    "bounded causal future location callbacks required")
  if (!is.null(members)) q(is.matrix(members) && is.numeric(members) &&
    identical(dim(members), c(as.integer(horizon), 51L)) && all(is.finite(members)),
    "all51 ordinary unit member factors required")
  force(spec); force(members); force(location); force(member_location); force(horizon)
  force(particles); force(ess_fraction); force(limits); force(gates)
  function(x, seed) {
    decoded <- gcat_decode(x, spec)
    # With no members, every normalized future transition integrates to one.
    if (is.null(members)) return(list(log_estimate = 0, complete = TRUE,
      diagnostic_thresholds_passed = TRUE, callback_calls = 0L,
      target = "normalized_future_law_integrated_exactly_no_cut", production_qualified = FALSE))
    q(exists("gcpv_smc", mode = "function", inherits = TRUE), "particle implementation must be loaded")
    parameters <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
    out <- gcpv_smc(parameters = parameters, location = location,
      scale = function(h, past, parameters) unname(parameters$sigma["Y"]),
      member_location = member_location,
      member_scale = function(h, past, parameters) unname(parameters$sigma["G"]),
      members = members, horizon = horizon, probability = spec$probability,
      particles = particles, ess_fraction = ess_fraction, seed = seed, limits = limits, gates = gates)
    list(log_estimate = out$log_normalizer_estimate, complete = out$complete,
      diagnostic_thresholds_passed = out$diagnostic_thresholds_passed,
      callback_calls = out$callback_calls, failure = out$failure,
      min_ess = if (nrow(out$diagnostics)) min(out$diagnostics$effective_sample_size) else NA_real_,
      min_unique_ancestors = if (nrow(out$diagnostics)) min(out$diagnostics$unique_initial_ancestors) else NA_integer_,
      full_parameter_dimensions = spec$dimension, source_scale_convention = "Y_future_G_members",
      member_weights = rep(1, 51L), production_qualified = FALSE)
  }
}
