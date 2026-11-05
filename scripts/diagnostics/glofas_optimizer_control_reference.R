# Generated H1 control functions and their exact partial score moments.
# No application inputs, scientific fits or production qualification. These
# controls contain member likelihood terms only: no prior, entropy or Jacobian.

gocr_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS optimizer control reference: ", why), call. = FALSE)
  invisible(TRUE)
}

gocr_h1_control <- function(members, probability = .2,
    offset = c(.1, log(.3 / 4) + 1 / 8), units = c(.2, .5),
    kind = c("exact", "frozen_scale", "adaptive_frozen_scale", "state_frozen_taylor2"),
    anchor_log_sigma = offset[2L]) {
  kind <- match.arg(kind)
  gocr_require(exists("gcpor_h1_elbo", mode = "function") &&
    exists("gcpor_expected_rho", mode = "function"),
    "source the independent optimizer reference first")
  gocr_require(is.numeric(members) && length(members) %in% c(0L, 1L, 51L) &&
    all(is.finite(members)) && is.numeric(probability) && length(probability) == 1L &&
    is.finite(probability) && probability > 0 && probability < 1 &&
    is.numeric(offset) && length(offset) == 2L && all(is.finite(offset)) &&
    is.numeric(units) && length(units) == 2L && all(is.finite(units)) && all(units > 0) &&
    is.numeric(anchor_log_sigma) && length(anchor_log_sigma) == 1L &&
    is.finite(anchor_log_sigma) && abs(anchor_log_sigma) <= 100,
    "finite fixed generated members, standardization and scale anchor required")
  gocr_require(requireNamespace("digest", quietly = TRUE), "digest required for declared control identity")
  force(members); force(probability); force(offset); force(units); force(kind); force(anchor_log_sigma)
  # The anchor is fixed before the independent outer draws. It is neither
  # fitted using the evaluated draws nor differentiated by this factory.
  frozen_inverse_scale <- exp(-anchor_log_sigma)
  M <- length(members)
  identity <- digest::digest(list(schema_version = "glofas_generated_H1_control_v1",
    members = members, probability = probability, offset = offset, units = units,
    kind = kind, anchor_log_sigma = anchor_log_sigma,
    equation = if (kind == "exact") "ordinary_AL_member_log_likelihood" else if (kind == "state_frozen_taylor2")
      "M_log_pq_minus_M_eta_minus_state_frozen_quadratic_inverse_scale_times_check_loss" else
        "M_log_pq_minus_M_eta_minus_frozen_inverse_scale_sum_check_loss",
    factory_body = deparse(body(gocr_h1_control))), algo = "sha256", serialize = TRUE)
  make_evaluate <- function(fixed_inverse_scale, fixed_anchor = anchor_log_sigma) {
    force(fixed_inverse_scale); force(fixed_anchor)
    function(point) {
      gocr_require(is.numeric(point) && length(point) == 2L && all(is.finite(point)),
        "finite standardized theta/log-scale control point required")
      if (M == 0L) return(0)
      physical <- offset + units * point
      residual <- members - physical[1L]
      delta <- physical[2L] - fixed_anchor
      inverse <- if (kind == "exact") exp(-physical[2L]) else if (kind == "state_frozen_taylor2")
        fixed_inverse_scale * (1 - delta + .5 * delta^2) else fixed_inverse_scale
      value <- M * log(probability * (1 - probability)) - M * physical[2L] -
        inverse * sum(residual * (probability - (residual < 0)))
      gocr_require(is.finite(value), "nonrepresentable control value; no clipping permitted")
      value
    }
  }
  fixed_evaluate <- make_evaluate(frozen_inverse_scale)
  factory <- function(mean, log_sd, factor = NULL) {
    L <- if (is.null(factor)) diag(2L) else factor
    physical_factor <- diag(units) %*% L
    physical_mean <- offset + units * mean
    q <- gcpor_gaussian_contract(physical_mean, log_sd, physical_factor)
    gocr_require(q$p == 2L, "two uncertain generated parameter coordinates required")
    # An adaptive anchor uses only the current deterministic variational state,
    # before drawing this batch. The resulting function is frozen for all
    # evaluations/moments in the batch. No derivative through this anchor is
    # included in E[score*c]. That would add a spurious partial_phi c term.
    state_frozen <- kind %in% c("adaptive_frozen_scale", "state_frozen_taylor2")
    inverse_scale <- if (state_frozen)
      exp(-physical_mean[2L]) else frozen_inverse_scale
    point_evaluate <- if (state_frozen)
      make_evaluate(inverse_scale, physical_mean[2L]) else fixed_evaluate
    source_identity <- if (state_frozen)
      digest::digest(list(fixed_inputs = identity, frozen_anchor = physical_mean[2L]),
        algo = "sha256", serialize = TRUE) else identity
    if (kind == "state_frozen_taylor2") {
      partial <- gocr_taylor2_moments(mean, log_sd, factor, members, probability,
        offset, units, anchor_log_sigma = physical_mean[2L])
      expected <- partial$expected_value; gradient_mean <- partial$score_mean
      gradient_log_sd <- partial$score_log_sd
    } else if (M == 0L) {
      expected <- 0; gradient_mean <- gradient_log_sd <- c(0, 0)
    } else if (kind == "exact") {
      # This is exactly member-ELBO minus no-member ELBO, evaluated without
      # subtracting the common (possibly large) prior, entropy and Jacobian.
      # Gaussian exponential tilting keeps the theta/log-scale covariance.
      V <- q$covariance; s <- sqrt(V[1L, 1L])
      residual <- members - physical_mean[1L] + V[1L, 2L]
      z <- residual / s; T <- exp(-physical_mean[2L] + V[2L, 2L] / 2)
      S <- sum(gcpor_expected_rho(residual, s, probability))
      D <- sum(probability - stats::pnorm(-z))
      B <- sum(stats::dnorm(z) / (2 * s))
      expected <- M * log(probability * (1 - probability)) - M * physical_mean[2L] - T * S
      gradient_mean <- units * c(T * D, -M + T * S)
      gradient_log_sd <- 2 * exp(2 * log_sd) *
        (-T * B * physical_factor[1L, ]^2 - .5 * T * S * physical_factor[2L, ]^2 -
          T * D * physical_factor[1L, ] * physical_factor[2L, ])
    } else {
      s <- sqrt(q$covariance[1L, 1L]); residual <- members - physical_mean[1L]
      z <- residual / s
      S <- sum(gcpor_expected_rho(residual, s, probability))
      D <- sum(probability - stats::pnorm(-z))
      B <- sum(stats::dnorm(z) / (2 * s))
      expected <- M * log(probability * (1 - probability)) -
        M * physical_mean[2L] - inverse_scale * S
      gradient_mean <- units * c(inverse_scale * D, -M)
      gradient_log_sd <- -2 * inverse_scale * B * exp(2 * log_sd) * physical_factor[1L, ]^2
    }
    gocr_require(all(is.finite(c(expected, gradient_mean, gradient_log_sd))),
      "nonfinite analytic control expectation or partial score moments")
    list(evaluate = point_evaluate, expected_value = as.numeric(expected),
      score_mean = as.numeric(gradient_mean), score_log_sd = as.numeric(gradient_log_sd),
      freeze_policy = if (kind == "exact") "exact_control" else "independent_frozen_control",
      moment_scope = "partial_outer_score_holding_control_fixed",
      source_identity = source_identity)
  }
  factory
}

# Exact PARTIAL outer-score moments for a fixed Taylor2 anchor. The anchor is
# an explicit argument so independent derivatives hold it fixed. Non-diagonal
# factors are rejected rather than silently discarding theta/eta dependence.
gocr_taylor2_moments <- function(mean, log_sd, factor = NULL, members,
    probability = .2, offset = c(.1, log(.3 / 4) + 1 / 8), units = c(.2, .5),
    anchor_log_sigma) {
  L <- if (is.null(factor)) diag(2L) else factor
  gocr_require(is.numeric(offset) && length(offset) == 2L && all(is.finite(offset)) &&
    is.numeric(units) && length(units) == 2L && all(is.finite(units)) && all(units > 0),
    "finite explicit two-coordinate standardization required")
  gocr_require(is.matrix(L) && is.numeric(L) && all(is.finite(L)) && identical(dim(L), c(2L, 2L)) &&
    all(L[row(L) != col(L)] == 0), "Taylor2 moments require an explicit diagonal fixed factor")
  F <- diag(units) %*% L
  q <- gcpor_gaussian_contract(offset + units * mean, log_sd, F)
  gcpor_h1_contract(members, probability, .1, .2, 4, .3)
  gocr_require(length(anchor_log_sigma) == 1L && is.finite(anchor_log_sigma) &&
    abs(anchor_log_sigma) <= 100, "finite independently frozen Taylor2 scale anchor required")
  physical_mean <- q$mean; V <- q$covariance
  s <- sqrt(V[1L, 1L]); residual <- members - physical_mean[1L]; z <- residual / s
  S <- sum(gcpor_expected_rho(residual, s, probability))
  D <- sum(probability - stats::pnorm(-z)); B <- sum(stats::dnorm(z) / (2 * s))
  d <- physical_mean[2L] - anchor_log_sigma
  A <- 1 - d + .5 * (d^2 + V[2L, 2L]); k <- exp(-anchor_log_sigma); M <- length(members)
  expected <- M * (log(probability * (1 - probability)) - physical_mean[2L]) - k * A * S
  gm <- units * c(k * A * D, -M - k * (-1 + d) * S)
  gs <- 2 * exp(2 * log_sd) * (-k * A * B * F[1L, ]^2 - .5 * k * S * F[2L, ]^2)
  gocr_require(all(is.finite(c(expected, gm, gs))), "nonfinite Taylor2 partial moments")
  list(expected_value = expected, score_mean = gm, score_log_sd = gs,
    moment_scope = "partial_outer_score_holding_control_fixed", anchor_log_sigma = anchor_log_sigma,
    original_reads = 0L, production_qualified = FALSE)
}

# Independent direct Normal integration of a frozen-scale check-loss control.
# Split at every AL kink so a low-order unsplit quadrature cannot falsely
# certify the score moments. This only checks the generated two-dimensional
# H1 control; it does not establish accuracy of a native H2 particle bound.
gocr_frozen_quadrature <- function(mean, log_sd, factor = NULL, members,
    probability = .2, offset = c(.1, log(.3 / 4) + 1 / 8), units = c(.2, .5),
    anchor_log_sigma = offset[2L]) {
  factory <- gocr_h1_control(members, probability, offset, units,
    kind = "frozen_scale", anchor_log_sigma = anchor_log_sigma)
  declared <- factory(mean, log_sd, factor)
  L <- if (is.null(factor)) diag(2L) else factor
  V <- tcrossprod(sweep(diag(units) %*% L, 2L, exp(log_sd), "*"))
  mt <- offset[1L] + units[1L] * mean[1L]
  me <- offset[2L] + units[2L] * mean[2L]
  s <- sqrt(V[1L, 1L]); cuts <- sort(unique(c(-Inf, (members - mt) / s, 0, Inf)))
  loss <- function(z) vapply(z, function(t) {
    e <- members - mt - s * t
    sum(e * (probability - (e < 0)))
  }, numeric(1L))
  expectation <- sum(vapply(seq_len(length(cuts) - 1L), function(i)
    stats::integrate(function(z) stats::dnorm(z) * loss(z), cuts[i], cuts[i + 1L],
      rel.tol = 1e-10, abs.tol = 1e-12, subdivisions = 1000L)$value, numeric(1L)))
  list(value = length(members) * (log(probability * (1 - probability)) - me) -
    exp(-anchor_log_sigma) * expectation,
    comparison_expected_value = declared$expected_value,
    original_reads = 0L, production_qualified = FALSE,
    integration = "split one-dimensional Normal quadrature of literal frozen-scale AL check loss")
}
