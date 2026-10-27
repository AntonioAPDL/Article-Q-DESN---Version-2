# R154 fixed-state references only. Sourcing this file never fits a model.
# All inputs and all certificate comparisons remain in original design units.
r522_gaussian_reference <- function(P, b) {
  stopifnot(is.matrix(P), nrow(P) == ncol(P), length(b) == nrow(P),
    all(is.finite(P)), all(is.finite(b)), identical(P, t(P)), all(diag(P) > 0))
  D <- 1 / sqrt(diag(P)); Ps <- (P * D) * rep(D, each = length(D))
  # Enforce only the common rounded symmetric product, never diagonal jitter.
  Ps[upper.tri(Ps)] <- t(Ps)[upper.tri(Ps)]
  U <- chol(Ps)
  theta <- backsolve(U, forwardsolve(t(U), D * b))
  beta <- D * as.numeric(theta)
  V <- (chol2inv(U) * D) * rep(D, each = length(D))
  residual <- as.numeric(P %*% beta - b)
  denominator <- as.numeric(abs(P) %*% abs(beta) + abs(b))
  component <- ifelse(denominator > 0, abs(residual) / denominator, 0)
  list(beta = beta, covariance = V, diagonal_scale = D, jitter_added = 0,
    componentwise_backward_error = max(component),
    normwise_backward_error = max(abs(residual)) /
      max(.Machine$double.xmin, norm(P, 'I') * max(abs(beta)) + max(abs(b))),
    inverse_residual_inf = norm(P %*% V - diag(length(b)), 'I'),
    original_precision_condition = kappa(P, exact = TRUE),
    scaled_precision_condition = kappa(Ps, exact = TRUE))
}

r522_elbo_reference <- function(prior, state, m, V, sigma, y, X, tau) {
  stopifnot(all(is.finite(m)), all(is.finite(V)), sigma > 0,
    tau > 0, tau < 1, nrow(X) == length(y), ncol(X) == length(m))
  n <- length(y); p <- length(m)
  A <- (1 - 2 * tau) / (tau * (1 - tau)); B <- 2 / (tau * (1 - tau))
  a <- 1 + 1.5 * n; b <- sigma * (a - 1); k <- a / b
  residual <- y - as.numeric(X %*% m)
  second <- pmax(rowSums((X %*% V) * X) + residual^2, 0)
  chi_raw <- (k / B) * second; psi_raw <- k * (2 + A^2 / B)
  chi <- pmax(chi_raw, 1e-12); psi <- max(psi_raw, 1e-12)
  ell <- sqrt(psi / chi)
  nu <- sqrt(chi / psi) * (1 + 1 / sqrt(chi * psi))
  # Exact shape-1/2 GIG identity. Same original constants and floor corrections.
  logc <- .5 * log(psi / (2 * pi)) + sqrt(chi * psi)
  correction <- .5 * ((chi - chi_raw) * ell + (psi - psi_raw) * nu)
  elogs <- log(b) - digamma(a)
  terms <- c(prior = prior$elbo_vb(state, list(m = m, V = V)),
    sigma_prior = -2 * elogs - k, latent_scale = -n * elogs,
    likelihood_constant = -(n / 2) * (log(2 * pi) + log(B) + elogs),
    beta_entropy = .5 * (p * (1 + log(2 * pi)) + 2 * sum(log(diag(chol(V))))),
    sigma_entropy = a + log(b) + lgamma(a) - (a + 1) * digamma(a),
    latent_cross = (k * A / B) * sum(residual),
    latent_normalizer = -sum(logc), floor_correction = sum(correction))
  list(objective = sum(terms), terms = terms,
    absolute_term_sum = sum(abs(terms)), chi_floor_count = sum(chi_raw < 1e-12),
    psi_floor_active = psi_raw < 1e-12,
    prior_boundary = 'pinned_original_RHS_elbo_same_state',
    record_kind = 'diagnostic_only_no_production_acceptance_authority')
}
