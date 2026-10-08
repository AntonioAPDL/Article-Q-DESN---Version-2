# Independent stationarity checks; production fitting remains on public CRAN APIs.
r129_namespace <- function(library) {
  ns <- loadNamespace('exdqlm', lib.loc = library)
  d <- utils::packageDescription('exdqlm', lib.loc = library)
  stopifnot(identical(as.character(d$Version), '1.1.1'), identical(d$Repository, 'CRAN'),
    identical(normalizePath(find.package('exdqlm')), normalizePath(file.path(library, 'exdqlm'))))
  ns
}

r129_prior <- function(ns, p, tau0, start = 'unit') {
  controls <- list(tau0 = tau0, shrink_intercept = FALSE,
    freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L)
  if (identical(start, 'dispersed')) {
    controls$init_tau <- tau0
    controls$init_lambda <- 10
    controls$init_c2 <- 100
  }
  get('.static_beta_prior_make', ns)(beta_prior = 'rhs_ns', p = p,
    b0 = rep(0, p), V0 = diag(1e6, p), beta_prior_controls = controls)
}

r129_rates <- function(s) {
  p <- s$p; idx <- if (s$shrink_intercept) seq_len(p) else seq.int(2L, p)
  c(log(s$b_lambda[idx]), log(s$b_nu[idx]), log(s$b_tau), log(s$b_xi), log(s$b_zeta))
}

r129_rhs_block_residual <- function(prior, state, m, V) {
  stopifnot(!state$shrink_intercept, !state$zeta2_is_fixed,
    state$p == length(m), all(dim(V) == c(length(m), length(m))))
  idx <- seq.int(2L, state$p)
  beta2 <- m^2 + diag(V)
  shapes <- c(state$a_lambda[idx] - 1, state$a_nu[idx] - 1,
    state$a_tau - (length(idx) + 1) / 2, state$a_xi - 1,
    state$a_zeta - prior$controls$a_zeta - length(idx) / 2)
  # Simultaneous coordinate equations use one variational state, not a CAVI sweep.
  expected <- c(.5 * beta2[idx] * state$a_tau / state$b_tau +
      state$a_nu[idx] / state$b_nu[idx],
    1 + state$a_lambda[idx] / state$b_lambda[idx],
    .5 * sum(beta2[idx] * state$a_lambda[idx] / state$b_lambda[idx]) +
      state$a_xi / state$b_xi,
    1 / prior$controls$tau0^2 + state$a_tau / state$b_tau,
    prior$controls$b_zeta + .5 * sum(beta2[idx]))
  stopifnot(all(is.finite(expected)), all(expected > 0))
  max(abs(shapes), abs(log(expected) - r129_rates(state)))
}

r129_reconstruct_rhs <- function(prior, m, V, max_iter = 20000L, tol = 1e-9) {
  state <- prior$init_vb(); residual <- Inf; stable <- 0L
  for (i in seq_len(max_iter)) {
    next_state <- prior$update_vb(state, list(m = m, V = V))
    residual <- max(abs(r129_rates(next_state) - r129_rates(state)))
    state <- next_state
    stable <- if (is.finite(residual) && residual <= tol) stable + 1L else 0L
    if (stable >= 5L) break
  }
  list(state = state, residual = residual, iterations = i, converged = stable >= 5L,
    precision = prior$beta_system_vb(state)$prec_diag)
}

r129_elbo <- function(ns, prior, state, m, V, sigma, y, X, tau) {
  n <- length(y); p <- length(m); A <- (1 - 2 * tau) / (tau * (1 - tau)); B <- 2 / (tau * (1 - tau))
  a <- 1 + 1.5 * n; b <- sigma * (a - 1); k <- a / b
  residual <- y - as.numeric(X %*% m)
  second <- pmax(rowSums((X %*% V) * X) + residual^2, 0)
  chi <- pmax((k / B) * second, 1e-12); psi <- pmax(k * (2 + A^2 / B), 1e-12)
  ell <- sqrt(psi / chi); nu <- sqrt(chi / psi) * (1 + 1 / sqrt(chi * psi))
  elogv <- get('.dqlm_gig_elog', ns)(.5, chi, psi)
  elogs <- log(b) - digamma(a)
  Hbeta <- .5 * (p * (1 + log(2 * pi)) + 2 * sum(log(diag(chol(V)))))
  Hsigma <- a + log(b) + lgamma(a) - (a + 1) * digamma(a)
  Hlatent <- get('.dqlm_gig_entropy', ns)(.5, chi, rep(psi, n), ell, nu, elogv)
  objective <- prior$elbo_vb(state, list(m = m, V = V)) - 2 * elogs - k -
    n * elogs - k * sum(nu) - (n / 2) * (log(2 * pi) + log(B) + elogs) -
    .5 * sum(elogv) - (k / (2 * B)) * sum(ell * second - 2 * A * residual + A^2 * nu) +
    Hbeta + Hsigma + Hlatent
  list(elbo = as.numeric(objective), ell = ell, nu = nu, second = second,
    residual = residual, kappa = k, a = a, b = b, A = A, B = B)
}

r129_certificate <- function(ns, X, y, m, V, sigma, tau, tau0, limits,
                             max_rhs_iter = 20000L) {
  stopifnot(nrow(X) == length(y), ncol(X) == length(m), all(dim(V) == c(length(m), length(m))),
    all(is.finite(X)), all(is.finite(y)), all(is.finite(m)), all(is.finite(V)),
    is.finite(sigma), sigma > 0, tau > 0, tau < 1, tau0 > 0)
  V <- .5 * (V + t(V)); p <- length(m)
  prior <- r129_prior(ns, p, tau0)
  first <- r129_reconstruct_rhs(prior, m, V, max_iter = max_rhs_iter)
  other_prior <- r129_prior(ns, p, tau0, 'dispersed')
  other <- r129_reconstruct_rhs(other_prior, m, V, max_iter = max_rhs_iter)
  rhs_agreement <- max(abs(log(first$precision) - log(other$precision)))
  current <- r129_elbo(ns, prior, first$state, m, V, sigma, y, X, tau)
  W <- (current$kappa / current$B) * current$ell
  P <- crossprod(X * sqrt(W)) + diag(first$precision, p)
  U <- chol(P)
  b <- (current$kappa / current$B) * (crossprod(X, current$ell * y) - current$A * colSums(X))
  solved <- as.numeric(backsolve(U, forwardsolve(t(U), b)))
  inverse_m <- as.numeric(chol2inv(U) %*% b)
  difference <- solved - m
  whitened <- U %*% difference
  new_V <- chol2inv(U)
  cov_error <- U %*% V %*% t(U) - diag(p)
  covariance_residual <- sqrt(sum(cov_error^2) / p)
  predictor_rms <- sqrt(mean(as.numeric(X %*% difference)^2))
  beta_residual <- sqrt(sum(whitened^2) / p)
  sigma_new_b <- 1 + sum(current$nu) + sum(current$ell * current$second -
    2 * current$A * current$residual + current$A^2 * current$nu) / (2 * current$B)
  sigma_residual <- abs(sigma_new_b / current$b - 1)
  rhs_next <- prior$update_vb(first$state, list(m = solved, V = new_V))
  rhs_lookahead_residual <- max(abs(r129_rates(rhs_next) - r129_rates(first$state)))
  rhs_joint_residual <- r129_rhs_block_residual(prior, first$state, m, V)
  new_sigma <- sigma_new_b / (current$a - 1)
  next_objective <- r129_elbo(ns, prior, rhs_next, solved, new_V, new_sigma, y, X, tau)$elbo
  elbo_residual <- abs(next_objective - current$elbo) / max(1, abs(current$elbo))
  measures <- list(beta_posterior_sd_rms = beta_residual, predictor_rms = predictor_rms,
    covariance_whitened_rms = covariance_residual, sigma_relative = sigma_residual,
    rhs_joint_log_rates = rhs_joint_residual, rhs_start_log_precision = rhs_agreement,
    elbo_relative = elbo_residual)
  checks <- vapply(names(measures), function(k) is.finite(measures[[k]]) &&
    measures[[k]] <= limits[[k]], logical(1))
  list(certified = all(checks) && first$converged && other$converged,
    certification = 'independent_same_state_AL_RHS_NS_block_stationarity_not_original_formal_flag',
    measures = measures, limits = limits, checks = as.list(checks),
    rhs_reconstruction = list(unit_converged = first$converged, dispersed_converged = other$converged,
      unit_iterations = first$iterations, dispersed_iterations = other$iterations,
      unit_residual = first$residual, dispersed_residual = other$residual),
    raw_reconstructed_elbo = current$elbo, raw_next_elbo = next_objective,
    precision_condition = kappa(P, exact = TRUE),
    mean_solve_relative_residual = sqrt(sum((P %*% solved - b)^2)) / sqrt(sum(b^2)),
    inverse_mean_relative_residual = sqrt(sum((P %*% inverse_m - b)^2)) / sqrt(sum(b^2)),
    inverse_vs_solve_max_beta = max(abs(inverse_m - solved)),
    rhs_lookahead_log_rates_not_stationarity_gate = rhs_lookahead_residual,
    diagnostic_rhs_shape = first$state$a_tau, shrunk_dimension = p - 1L,
    initialization_changes_prior = FALSE, prior_center = rep(0, p),
    reconstructed_rhs_state = first$state, beta_covariance = V,
    likelihood_scale_state = list(a = current$a, b = current$b),
    latent_state = list(ell = current$ell, nu = current$nu))
}
