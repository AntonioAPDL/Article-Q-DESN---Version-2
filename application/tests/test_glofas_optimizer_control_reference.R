# Independent generated control/moment checks. No model or runtime reads.
local({
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_optimizer_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_optimizer_control_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  finite <- function(fun, x) vapply(seq_along(x), function(j) {
    a <- b <- x; a[j] <- a[j] + 1e-6; b[j] <- b[j] - 1e-6
    (fun(a) - fun(b)) / 2e-6
  }, numeric(1L))
  offset <- c(.1, log(.3 / 4) + 1 / 8); units <- c(.2, .5)
  mean <- c(.15, -.3); log_sd <- c(-.6, -.8); point <- c(.2, -.7)
  members <- seq(-.3, .7, length.out = 51L)
  factors <- list(NULL, matrix(c(1, .4, -.2, 1), 2L))
  for (p in c(.2, .5, .8)) for (L in factors) {
    exact <- gocr_h1_control(members, p, offset, units, "exact")
    fixed <- gocr_h1_control(members, p, offset, units, "frozen_scale")
    cv <- exact(mean, log_sd, L); frozen <- fixed(mean, log_sd, L)
    ok(setequal(names(cv), c("evaluate", "expected_value", "score_mean", "score_log_sd",
      "freeze_policy", "moment_scope", "source_identity")))
    physical <- offset + units * point
    literal <- sum(gcpr_log_al(members, physical[1L], p, exp(physical[2L])))
    ok(abs(cv$evaluate(point) - literal) < 1e-10)
    ok(identical(cv$freeze_policy, "exact_control") &&
      identical(frozen$freeze_policy, "independent_frozen_control") &&
      identical(cv$moment_scope, "partial_outer_score_holding_control_fixed") &&
      grepl("^[a-f0-9]{64}$", cv$source_identity))
    ok(identical(cv$source_identity, exact(mean + .1, log_sd - .1, L)$source_identity))
    F <- diag(units) %*% if (is.null(L)) diag(2L) else L
    member_elbo <- gcpor_h1_elbo(offset + units * mean, log_sd, F, members, p)
    no_member_elbo <- gcpor_h1_elbo(offset + units * mean, log_sd, F, probability = p)
    difference <- member_elbo$gradient - no_member_elbo$gradient
    ok(abs(cv$expected_value - (member_elbo$value - no_member_elbo$value)) < 1e-9 &&
      max(abs(c(cv$score_mean, cv$score_log_sd) - c(units * difference[1:2], difference[3:4]))) < 1e-9)
    independent <- gcpor_h1_conditional_gh_elbo(offset + units * mean, log_sd, F,
      members = members, probability = p, nodes = 48L)$value -
      gcpor_h1_conditional_gh_elbo(offset + units * mean, log_sd, F,
        probability = p, nodes = 48L)$value
    ok(abs(cv$expected_value - independent) < 1e-9)
    pack <- c(mean, log_sd)
    derivative <- finite(function(x) exact(x[1:2], x[3:4], L)$expected_value, pack)
    ok(max(abs(derivative - c(cv$score_mean, cv$score_log_sd))) < 1e-7)
    quad <- gocr_frozen_quadrature(mean, log_sd, L, members, p, offset, units)
    ok(abs(quad$value - frozen$expected_value) < 1e-9 && !quad$production_qualified)
    independent_gradient <- finite(function(x) gocr_frozen_quadrature(x[1:2], x[3:4], L,
      members, p, offset, units)$value, pack)
    ok(max(abs(independent_gradient - c(frozen$score_mean, frozen$score_log_sd))) < 1e-7)
  }

  # Empty products contribute zero in every coordinate. Subtracting the
  # historical ELBO cancels its entropy, prior and Jacobian rather than
  # introducing them a second time into the future control correction.
  for (kind in c("exact", "frozen_scale", "adaptive_frozen_scale", "state_frozen_taylor2")) {
    c0 <- gocr_h1_control(numeric(), kind = kind)(mean, log_sd)
    ok(c0$evaluate(point) == 0 && c0$expected_value == 0 &&
      max(abs(c(c0$score_mean, c0$score_log_sd))) == 0)
  }
  for (anchor in c(-2, -5)) {
    c0 <- gocr_h1_control(members, kind = "frozen_scale", anchor_log_sigma = anchor)
    a <- c0(mean, log_sd); b <- c0(mean + .2, log_sd)
    ok(abs(a$evaluate(point) - b$evaluate(point)) < 1e-12 &&
      identical(a$source_identity, b$source_identity))
  }
  a <- gocr_h1_control(members, kind = "frozen_scale", anchor_log_sigma = -2)(mean, log_sd)
  b <- gocr_h1_control(members, kind = "frozen_scale", anchor_log_sigma = -5)(mean, log_sd)
  ok(!identical(a$source_identity, b$source_identity) && abs(a$evaluate(point) - b$evaluate(point)) > 1)

  adaptive_factory <- gocr_h1_control(members, kind = "adaptive_frozen_scale")
  adaptive <- adaptive_factory(mean, log_sd)
  same_anchor <- gocr_h1_control(members, kind = "frozen_scale",
    anchor_log_sigma = offset[2L] + units[2L] * mean[2L])(mean, log_sd)
  ok(max(abs(c(adaptive$expected_value, adaptive$score_mean, adaptive$score_log_sd) -
    c(same_anchor$expected_value, same_anchor$score_mean, same_anchor$score_log_sd))) < 1e-12 &&
    abs(adaptive$evaluate(point) - same_anchor$evaluate(point)) < 1e-12)
  old_value <- adaptive$evaluate(point)
  next_control <- adaptive_factory(mean + c(0, .1), log_sd)
  ok(abs(adaptive$evaluate(point) - old_value) < 1e-12 &&
    !identical(adaptive$source_identity, next_control$source_identity) &&
    abs(adaptive$evaluate(point) - next_control$evaluate(point)) > .1)
  total_adaptive <- finite(function(m) adaptive_factory(m, log_sd)$expected_value, mean)
  ok(abs(total_adaptive[2L] - adaptive$score_mean[2L]) > 1 &&
    adaptive$score_mean[2L] == -length(members) * units[2L])

  # Taylor2 controls keep the first/second log-scale terms as well as the
  # normalization. Tensor independence is used only under explicit diagonal q.
  # Quadrature of the literal polynomial/check loss is independent of the
  # closed moment formula, and its derivatives hold the anchor FIXED.
  taylor_quad <- function(mean, log_sd, factor, p, anchor) {
    theta_quad <- gocr_frozen_quadrature(mean, log_sd, factor, members, p,
      offset, units, anchor_log_sigma = 0)
    me <- offset[2L] + units[2L] * mean[2L]
    S <- length(members) * (log(p * (1 - p)) - me) - theta_quad$value
    L <- if (is.null(factor)) diag(2L) else factor
    sd_eta <- abs(units[2L] * L[2L, 2L]) * exp(log_sd[2L])
    z <- gcpor_normal_quadrature(16L); delta <- me + sd_eta * z$nodes - anchor
    A <- sum(z$weights * (1 - delta + .5 * delta^2))
    length(members) * (log(p * (1 - p)) - me) - exp(-anchor) * A * S
  }
  for (L in list(NULL, diag(c(.7, 1.2)))) for (p in c(.2, .5, .8)) {
    anchor <- offset[2L] - .3
    partial <- gocr_taylor2_moments(mean, log_sd, L, members, p, offset, units, anchor)
    quad <- taylor_quad(mean, log_sd, L, p, anchor)
    ok(abs(partial$expected_value - quad) < 1e-9)
    numerical <- finite(function(x) taylor_quad(x[1:2], x[3:4], L, p, anchor), c(mean, log_sd))
    ok(max(abs(c(partial$score_mean, partial$score_log_sd) - numerical)) < 1e-7)
    factory <- gocr_h1_control(members, p, offset, units, "state_frozen_taylor2")
    cv <- factory(mean, log_sd, L); a <- offset[2L] + units[2L] * mean[2L]
    literal <- offset + units * point; residual <- members - literal[1L]; delta <- literal[2L] - a
    value <- length(members) * (log(p * (1 - p)) - literal[2L]) -
      exp(-a) * (1 - delta + .5 * delta^2) * sum(residual * (p - (residual < 0)))
    ok(abs(cv$evaluate(point) - value) < 1e-10)
    held <- gocr_taylor2_moments(mean, log_sd, L, members, p, offset, units, a)
    ok(max(abs(c(cv$expected_value, cv$score_mean, cv$score_log_sd) -
      c(held$expected_value, held$score_mean, held$score_log_sd))) < 1e-12)
    total <- finite(function(m) factory(m, log_sd, L)$expected_value, mean)
    ok(abs(total[2L] - cv$score_mean[2L]) > .01)
  }

  # Counterexample: if c_phi(x)=phi*x and q_phi=N(phi,1), total d E[c_phi]
  # contains E[partial_phi c_phi]. The score correction needs ONLY the partial
  # outer-score moment with the control held fixed. Adding the total derivative
  # instead creates a spurious term even for this exact polynomial target.
  phi <- 1.3; z <- gcpor_normal_quadrature(16L); x <- phi + z$nodes
  target_gradient <- sum(z$weights * z$nodes * x^2)
  residual_gradient <- sum(z$weights * z$nodes * (x^2 - phi * x))
  partial <- sum(z$weights * z$nodes * phi * x)
  total <- finite(function(m) m^2, phi)
  ok(abs(target_gradient - 2 * phi) < 1e-12 &&
    abs(residual_gradient + partial - target_gradient) < 1e-12)
  ok(abs(total - 2 * phi) < 1e-8 &&
    abs(residual_gradient + total - target_gradient - phi) < 1e-8)

  # H1 exact-control success cannot certify H2 stochastic log-normalizers.
  # Subtracting any fixed control and adding its exact expectation reduces
  # gradient variance but does not undo the finite-particle Jensen gap.
  G2 <- matrix(rep(c(.15, .22), 51L), 2L, 51L)
  c1 <- gocr_h1_control(G2[1L, ], probability = .2)(mean, log_sd)$evaluate(point)
  for (lag in c(-.35, .35)) {
    gap <- gcpr_log_bound_one_particle(.1, .15, G2, p = .2, lag = lag)
    corrected <- gap$expected_log_estimate - c1 + c1
    ok(gap$Jensen_gap > .01 && corrected < gap$exact_log_evidence &&
      abs(corrected - gap$expected_log_estimate) < 1e-10)
  }
  gap_a <- gcpr_log_bound_one_particle(.1, .07, G2, p = .2)$Jensen_gap
  gap_b <- gcpr_log_bound_one_particle(.1, .2, G2, p = .2)$Jensen_gap
  ok(abs(gap_a - gap_b) > .01)

  reject(gocr_h1_control(rep(.1, 50L)))
  reject(gocr_h1_control(members, probability = 0))
  reject(gocr_h1_control(members, units = c(.2, 0)))
  reject(gocr_h1_control(members, anchor_log_sigma = Inf))
  reject(gocr_h1_control(members)(mean, log_sd, matrix(1, 2L, 2L)))
  reject(gocr_h1_control(members)(mean, log_sd)$evaluate(c(.1, NA_real_)))
  reject(gocr_h1_control(members, kind = "state_frozen_taylor2")(mean, log_sd,
    matrix(c(1, .2, 0, 1), 2L)))
  reject(gocr_taylor2_moments(mean, log_sd, members = members, units = c(.2, -1),
    anchor_log_sigma = -2))
  cat(sprintf("GLOFAS_OPTIMIZER_CONTROL_REFERENCE_PASS checks=%d original_reads=0 application_fits=0 production_qualified=FALSE\n", checks))
})
