# Staged R154 toy-only consumer. Sourcing defines functions; it runs no optimizer.
# A valid imported factor state is a new initialization, never an exact resume.
r524_toy_limits <- function(X, y, max_iter = 0L) {
  stopifnot(is.matrix(X), identical(attr(X, 'r524_origin'), 'synthetic_toy'),
    nrow(X) == length(y), nrow(X) >= 1L, nrow(X) <= 128L,
    ncol(X) >= 2L, ncol(X) <= 32L, all(is.finite(X)), all(is.finite(y)),
    max_iter >= 0L, max_iter <= 30L)
  invisible(TRUE)
}

r524_target_key <- function(X, y, tau, prior, b0, V0, a_sigma, b_sigma) {
  digest::digest(list(schema = 'r524_synthetic_target_v1', X = X, y = y,
    tau = tau, prior_type = prior$type, controls = prior$controls,
    b0 = b0, V0 = V0, sigma_prior = c(a_sigma, b_sigma)), algo = 'sha256')
}

r524_close <- function(actual, expected) {
  isTRUE(all.equal(actual, expected, tolerance = 1e-12, check.attributes = TRUE))
}

r524_validate_state <- function(state, X, y, tau, prior, b0, V0,
                                a_sigma, b_sigma, ns) {
  r524_toy_limits(X, y)
  n <- nrow(X); p <- ncol(X)
  allowed <- c('schema', 'origin', 'kind', 'target_key', 'qbeta', 'qv', 'qsig',
    'rhs_state', 'prior_controls', 'source_provenance')
  stopifnot(is.list(state), length(state) == length(allowed), !anyDuplicated(names(state)),
    setequal(names(state), allowed),
    identical(state$schema, 'r524_full_factors_new_initialization_v1'),
    identical(state$origin, 'synthetic_toy'),
    state$kind %in% c('full_stock_checkpoint_new_initialization',
      'conditional_reconstruction_new_initialization',
      'synthetic_valid_factor_product_new_initialization'),
    identical(prior$type, 'rhs_ns'), all(b0 == 0),
    identical(unname(V0), unname(diag(1e6, p))), a_sigma == 1, b_sigma == 1,
    identical(state$target_key, r524_target_key(X, y, tau, prior, b0, V0, a_sigma, b_sigma)),
    identical(state$prior_controls, prior$controls),
    length(state$qbeta$m) == p, all(is.finite(state$qbeta$m)),
    is.matrix(state$qbeta$V), all(dim(state$qbeta$V) == c(p, p)),
    all(is.finite(state$qbeta$V)), r524_close(state$qbeta$V, t(state$qbeta$V)))
  stopifnot(setequal(names(state$qbeta), c('m', 'V')),
    setequal(names(state$qsig), c('a', 'b', 'E_sigma', 'E_inv_sigma', 'E_log_sigma')),
    setequal(names(state$qv), c('chi', 'psi', 'E_v', 'E_inv_v', 'E_log_v')))
  chol(state$qbeta$V)  # Validate SPD; do not silently symmetrize/replace V.
  q <- state$qsig
  stopifnot(q$a == a_sigma + 1.5 * n, length(q$b) == 1L,
    is.finite(q$b), q$b >= 1e-12,
    r524_close(q$E_sigma, q$b / (q$a - 1)),
    r524_close(q$E_inv_sigma, q$a / q$b),
    r524_close(q$E_log_sigma, log(q$b) - digamma(q$a)))
  v <- state$qv
  stopifnot(length(v$chi) == n, length(v$psi) == 1L,
    all(is.finite(v$chi)), all(v$chi >= 1e-12),
    is.finite(v$psi), v$psi >= 1e-12,
    r524_close(v$E_inv_v, sqrt(v$psi / v$chi)),
    r524_close(v$E_v, sqrt(v$chi / v$psi) * (1 + 1 / sqrt(v$chi * v$psi))),
    r524_close(v$E_log_v, get('.dqlm_gig_elog', ns)(.5, v$chi, v$psi)))
  # Import valid factors as stored. Do not recondition chi/psi on current sigma:
  # stock q(v) precedes q(sigma), so those conditionals usually differ.
  rhs <- state$rhs_state
  stopifnot(rhs$p == p, identical(rhs$prior_type, 'rhs_ns'),
    identical(rhs$shrink_intercept, FALSE), identical(rhs$zeta2_is_fixed, FALSE),
    prior$controls$freeze_tau_iters == 0, prior$controls$freeze_tau_warmup_iters == 0)
  for (key in c('a_lambda', 'b_lambda', 'a_nu', 'b_nu',
                'a_tau', 'b_tau', 'a_xi', 'b_xi', 'a_zeta', 'b_zeta')) {
    stopifnot(length(rhs[[key]]) > 0L, all(is.finite(rhs[[key]])), all(rhs[[key]] > 0))
  }
  for (key in c('a_lambda', 'b_lambda', 'a_nu', 'b_nu')) stopifnot(length(rhs[[key]]) == p)
  for (key in c('a_tau', 'b_tau', 'a_xi', 'b_xi', 'a_zeta', 'b_zeta')) stopifnot(length(rhs[[key]]) == 1L)
  precision <- prior$beta_system_vb(state$rhs_state)$prec_diag
  stopifnot(length(precision) == p, all(is.finite(precision)), all(precision > 0))
  prior_value <- prior$elbo_vb(state$rhs_state, state$qbeta)
  stopifnot(length(prior_value) == 1L, is.finite(prior_value))
  state
}

r524_snapshot <- function(fit, prior, source_kind = 'full_stock_checkpoint_new_initialization') {
  r524_toy_limits(fit$X, fit$y)
  p <- ncol(fit$X)
  list(schema = 'r524_full_factors_new_initialization_v1', origin = 'synthetic_toy',
    kind = source_kind,
    target_key = r524_target_key(fit$X, fit$y, fit$p0, prior, rep(0, p), diag(1e6, p), 1, 1),
    qbeta = fit$qbeta, qv = fit$qv, qsig = fit$qsig,
    rhs_state = fit$beta_prior$state, prior_controls = prior$controls,
    source_provenance = list(source_iterations = fit$iter,
      source_converged_not_inherited = fit$converged,
      optimizer_resume_claimed = FALSE, resets_iteration_stability_formal_trace = TRUE))
}

r524_explicit_factor_elbo <- function(ns, prior, state, X, y, tau) {
  r524_toy_limits(X, y)
  n <- length(y); p <- ncol(X)
  m <- state$qbeta$m; V <- state$qbeta$V; v <- state$qv; q <- state$qsig
  A <- (1 - 2 * tau) / (tau * (1 - tau)); B <- 2 / (tau * (1 - tau))
  residual <- y - as.numeric(X %*% m)
  second <- rowSums((X %*% V) * X) + residual^2
  elogs <- log(q$b) - digamma(q$a); k <- q$a / q$b
  Hlatent <- get('.dqlm_gig_entropy', ns)(.5, v$chi, rep(v$psi, n),
    v$E_inv_v, v$E_v, v$E_log_v)
  terms <- c(prior = prior$elbo_vb(state$rhs_state, state$qbeta),
    sigma_prior = -2 * elogs - k,
    latent_prior = -n * elogs - k * sum(v$E_v),
    likelihood = -(n / 2) * (log(2 * pi) + log(B) + elogs) -
      .5 * sum(v$E_log_v) - (k / (2 * B)) *
      sum(v$E_inv_v * second - 2 * A * residual + A^2 * v$E_v),
    Hbeta = .5 * (p * (1 + log(2 * pi)) + 2 * sum(log(diag(chol(V))))),
    Hsigma = q$a + log(q$b) + lgamma(q$a) - (q$a + 1) * digamma(q$a),
    Hlatent = Hlatent)
  list(objective = sum(terms), terms = as.list(terms),
    state_semantics = 'explicit_imported_factors_not_reconditioned_r129_state')
}

r524_make_toy_engine <- function(ns) {
  original <- get('.run_static_dqlm_cavi', ns)
  expressions <- as.list(body(original))
  for_index <- which(vapply(expressions, function(e)
    is.call(e) && identical(e[[1L]], as.name('for')), logical(1)))
  stopifnot(length(for_index) == 1L)
  gate <- quote({
    stopifnot(identical(Sys.getenv('R154_TOY_ROOT_ADMITTED'), '1'))
    r524_toy_limits(X, y, max_iter)
  })
  restore <- quote({
    if (!is.null(init$full_state)) {
      imported <- r524_restore_bound(init$full_state, X, y, p0,
        beta_prior_obj, b0, V0, a_sigma, b_sigma)
      m_beta <- imported$qbeta$m; V_beta <- imported$qbeta$V
      beta_state <- imported$rhs_state
      chi <- imported$qv$chi; psi <- imported$qv$psi
      ell <- imported$qv$E_inv_v; nu <- imported$qv$E_v
      mlogv <- imported$qv$E_log_v
      a_q <- imported$qsig$a; b_q <- imported$qsig$b
      kappa <- imported$qsig$E_inv_sigma
      seq.sigma <- imported$qsig$E_sigma
      # Original initialization has already reset all optimizer bookkeeping.
      stopifnot(iter == 0L, stable_count == 0L, !converged,
        length(elbo_trace) == 0L)
      # Preserve RHS internal schedule context with the supplied factors. This
      # toy scope requires zero freeze controls; source RHS counts are not AL
      # optimizer iterations and are never presented as an exact resume.
    }
  })
  # Keep all original update/objective/stop/sampling expressions byte-for-byte.
  expressions <- append(expressions, list(restore), after = for_index - 1L)
  expressions <- append(expressions, list(gate), after = 1L)
  modified <- original; body(modified) <- as.call(expressions)
  child_env <- new.env(parent = environment(original))
  child_env$r524_toy_limits <- r524_toy_limits
  child_env$r524_restore_bound <- function(...) r524_validate_state(..., ns = ns)
  environment(modified) <- child_env
  attr(modified, 'r524_original_body_sha256') <- digest::digest(body(original), algo = 'sha256')
  attr(modified, 'r524_scope') <- 'toy_only_no_production_dimensions_or_posterior_authority'
  modified
}

r524_independent_one_block <- function(ns, prior, state, X, y, tau) {
  # Independent explicit map; no call to either stock or modified CAVI engine.
  # The original prior closure is deliberately shared and documented.
  r524_toy_limits(X, y)
  n <- length(y); p <- ncol(X)
  A <- (1 - 2 * tau) / (tau * (1 - tau)); B <- 2 / (tau * (1 - tau))
  k <- state$qsig$a / state$qsig$b; ell <- state$qv$E_inv_v
  system <- prior$beta_system_vb(state$rhs_state)
  P <- crossprod(X * sqrt((k / B) * ell)) + system$Prec
  U <- chol(P)  # No new jitter: independently verifies well-conditioned toys.
  b <- system$h + (k / B) * (crossprod(X, ell * y) - A * colSums(X))
  m <- as.numeric(backsolve(U, forwardsolve(t(U), b))); V <- chol2inv(U)
  rhs <- prior$update_vb(state$rhs_state, list(m = m, V = V))
  residual <- y - as.numeric(X %*% m)
  second <- rowSums((X %*% V) * X) + residual^2
  chi <- pmax((k / B) * second, 1e-12)
  psi <- max(k * (2 + A^2 / B), 1e-12)
  inv_v <- sqrt(psi / chi)
  E_v <- sqrt(chi / psi) * (1 + 1 / sqrt(chi * psi))
  elog_v <- get('.dqlm_gig_elog', ns)(.5, chi, psi)
  a <- 1 + 1.5 * n
  rate <- max(1 + sum(E_v) + sum(inv_v * second - 2 * A * residual + A^2 * E_v) / (2 * B), 1e-12)
  next_state <- state
  next_state$qbeta <- list(m = m, V = V)
  next_state$rhs_state <- rhs
  next_state$qv <- list(chi = chi, psi = psi, E_v = E_v,
    E_inv_v = inv_v, E_log_v = elog_v)
  next_state$qsig <- list(a = a, b = rate, E_sigma = rate / (a - 1),
    E_inv_sigma = a / rate, E_log_sigma = log(rate) - digamma(a))
  list(state = next_state, objective = r524_explicit_factor_elbo(ns, prior, next_state, X, y, tau),
    precision_condition = kappa(P, exact = TRUE), source = 'independent_explicit_block_shared_original_prior')
}
