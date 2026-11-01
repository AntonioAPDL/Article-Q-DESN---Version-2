# New project consumer: only root-admitted exact real targets; frozen toys untouched.
# Definitions only. No matrix operation or optimizer executes while sourcing.
r525_allowed_targets <- c(
 'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75',
 'iq_AT_r134_7a422c0c3473f81f_t1.632090846764e-03_s1_al0.50')
r525_closed_data_limits <- function(ctx, X, y, max_iter = 0L) {
  stopifnot(identical(Sys.getenv('R154_PROJECT_ROOT_ADMITTED'), '1'),
    ctx$target_name %in% r525_allowed_targets,
    identical(ctx$origin, 'sealed_real_target_project_consumer'),
    identical(ctx$original_manifest_sha256, 'aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8'),
    identical(ctx$units, 'original_design_and_response'),
    identical(ctx$prior$family, 'rhs_ns'), identical(ctx$prior$center, 'zero'),
    identical(ctx$prior$shrink_intercept, FALSE), ctx$prior$sigma_a == 1,
    ctx$prior$sigma_b == 1, ctx$prior$freeze_tau_iters == 0,
    ctx$prior$freeze_tau_warmup_iters == 0,
    nrow(X) == ctx$n, ncol(X) == ctx$p, length(y) == ctx$n,
    ctx$n == 48576L, ctx$p %in% c(417L, 577L),
    max_iter >= 0L, max_iter <= 300L, all(is.finite(X)), all(is.finite(y)))
  if (identical(ctx$target_name, r525_allowed_targets[[1L]]))
    stopifnot(ctx$p == 417L, ctx$tau == .75, ctx$tau0 == 0.0022915214919211734)
  else stopifnot(ctx$p == 577L, ctx$tau == .5, ctx$tau0 == 0.0016320908467640013)
  invisible(TRUE)
}

r525_close <- function(actual, expected) {
  isTRUE(all.equal(actual, expected, tolerance = 1e-12, check.attributes = TRUE))
}

r525_validate_state <- function(state, X, y, tau, prior, b0, V0,
                                a_sigma, b_sigma, ns, ctx) {
  r525_closed_data_limits(ctx, X, y)
  n <- nrow(X); p <- ncol(X)
  allowed <- c('schema', 'origin', 'kind', 'target_key', 'qbeta', 'qv', 'qsig',
    'rhs_state', 'prior_controls', 'source_provenance')
  stopifnot(is.list(state), length(state) == length(allowed), !anyDuplicated(names(state)),
    setequal(names(state), allowed),
    identical(state$schema, 'r154_project_full_factors_v1'),
    identical(state$origin, 'sealed_real_target_project_consumer'),
    state$kind %in% c('conditional_reconstruction_new_initialization',
      'project_new_attempt_full_factors'),
    identical(prior$type, 'rhs_ns'), all(b0 == 0),
    identical(unname(V0), unname(diag(1e6, p))), a_sigma == 1, b_sigma == 1,
    identical(state$target_key, ctx$posterior_target_sha256),
    identical(state$prior_controls, prior$controls),
    length(state$qbeta$m) == p, all(is.finite(state$qbeta$m)),
    is.matrix(state$qbeta$V), all(dim(state$qbeta$V) == c(p, p)),
    all(is.finite(state$qbeta$V)), r525_close(state$qbeta$V, t(state$qbeta$V)))
  stopifnot(setequal(names(state$qbeta), c('m', 'V')),
    setequal(names(state$qsig), c('a', 'b', 'E_sigma', 'E_inv_sigma', 'E_log_sigma')),
    setequal(names(state$qv), c('chi', 'psi', 'E_v', 'E_inv_v', 'E_log_v')))
  chol(state$qbeta$V)  # Validate SPD; do not silently symmetrize/replace V.
  q <- state$qsig
  stopifnot(q$a == a_sigma + 1.5 * n, length(q$b) == 1L,
    is.finite(q$b), q$b >= 1e-12,
    r525_close(q$E_sigma, q$b / (q$a - 1)),
    r525_close(q$E_inv_sigma, q$a / q$b),
    r525_close(q$E_log_sigma, log(q$b) - digamma(q$a)))
  v <- state$qv
  stopifnot(length(v$chi) == n, length(v$psi) == 1L,
    all(is.finite(v$chi)), all(v$chi >= 1e-12),
    is.finite(v$psi), v$psi >= 1e-12,
    r525_close(v$E_inv_v, sqrt(v$psi / v$chi)),
    r525_close(v$E_v, sqrt(v$chi / v$psi) * (1 + 1 / sqrt(v$chi * v$psi))),
    r525_close(v$E_log_v, get('.dqlm_gig_elog', ns)(.5, v$chi, v$psi)))
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

r525_explicit_factor_elbo <- function(ns, prior, state, X, y, tau, ctx) {
  r525_closed_data_limits(ctx, X, y)
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

r525_factor_state <- function(frame, ctx, kind) {
  grab <- function(name) get(name, envir = frame, inherits = FALSE)
  a <- grab('a_q'); b <- grab('b_q')
  list(schema = 'r154_project_full_factors_v1',
    origin = ctx$origin, kind = kind,
    target_key = ctx$posterior_target_sha256,
    qbeta = list(m = grab('m_beta'), V = grab('V_beta')),
    qv = list(chi = grab('chi'), psi = grab('psi'), E_v = grab('nu'),
      E_inv_v = grab('ell'), E_log_v = grab('mlogv')),
    qsig = list(a = a, b = b, E_sigma = b / (a - 1),
      E_inv_sigma = grab('kappa'), E_log_sigma = log(b) - digamma(a)),
    rhs_state = grab('beta_state'), prior_controls = grab('beta_prior_obj')$controls,
    source_provenance = list(source = ctx$source, data_references = ctx$data_references,
      original_failed_bindings = ctx$original_failed,
      prior_attempt_iterations = 300L, new_attempt_index = 1L,
      new_completed_sweeps = grab('iter'), exact_optimizer_resume = FALSE))
}

r525_checkpoint <- function(frame, ctx, output) {
  iter <- get('iter', frame); stopifnot(iter >= 1L, iter <= 300L)
  folder <- file.path(output, 'checkpoints', sprintf('sweep_%04d', iter))
  stopifnot(dir.create(folder, recursive = FALSE))
  state <- r525_factor_state(frame, ctx, 'project_new_attempt_full_factors')
  optimizer <- list(completed_sweep = iter,
    stable_count = get('stable_count', frame), step = get('step', frame),
    stock_controls = get('controls', frame),
    raw_formal_stop_pending = isTRUE(get('step', frame)$stop_now),
    formal_flag_before_unchanged_stock_stop_check = get('converged', frame),
    elbo_trace = get('elbo_trace', frame), seq_sigma = get('seq.sigma', frame),
    delta_beta = get('delta_beta', frame), delta_sigma = get('delta_sigma', frame),
    delta_elbo = get('delta_elbo', frame),
    RNG_kind = RNGkind(), RNG_before_post_sampling = get('.Random.seed', .GlobalEnv),
    resume_supported_by_this_adapter = FALSE)
  path <- file.path(folder, 'full_state.rds')
  saveRDS(list(factors = state, optimizer = optimizer,
    data_references = ctx$data_references, source = ctx$source), path, compress = FALSE)
  entry <- list(completed_sweep = iter,
    state_pin = list(path = path, sha256 = digest::digest(path, file = TRUE, algo = 'sha256')),
    contains_all_factors_and_schedules = TRUE)
  con <- file(file.path(folder, 'completed_evidence.json'), 'wx'); on.exit(close(con))
  writeLines(jsonlite::toJSON(entry, auto_unbox = TRUE, pretty = TRUE, digits = 17), con)
  paths <- list.files(output, recursive = TRUE, full.names = TRUE)
  sizes <- file.info(paths)$size
  stopifnot(sum(sizes, na.rm = TRUE) <= ctx$disk_bytes)
  ctx$checkpoint_entries[[length(ctx$checkpoint_entries) + 1L]] <- entry
  invisible(NULL)
}

r525_make_engine <- function(ns, ctx, output) {
  original <- get('.run_static_dqlm_cavi', ns)
  body_items <- as.list(body(original))
  for_index <- which(vapply(body_items, function(e)
    is.call(e) && identical(e[[1L]], as.name('for')), logical(1)))
  stopifnot(length(for_index) == 1L)
  loop <- body_items[[for_index]]; loop_items <- as.list(loop[[4L]])
  stop_index <- which(vapply(loop_items, function(e)
    is.call(e) && identical(e[[1L]], as.name('if')) &&
      identical(e[[2L]], quote(step$stop_now)), logical(1)))
  stopifnot(length(stop_index) == 1L)
  loop_items <- append(loop_items, list(quote(r525_checkpoint_bound(environment()))),
    after = stop_index - 1L)
  loop[[4L]] <- as.call(loop_items); body_items[[for_index]] <- loop
  restore <- quote({
    stopifnot(!is.null(init$full_state))
    imported <- r525_restore_bound(init$full_state, X, y, p0,
      beta_prior_obj, b0, V0, a_sigma, b_sigma)
    m_beta <- imported$qbeta$m; V_beta <- imported$qbeta$V
    beta_state <- imported$rhs_state
    chi <- imported$qv$chi; psi <- imported$qv$psi
    ell <- imported$qv$E_inv_v; nu <- imported$qv$E_v; mlogv <- imported$qv$E_log_v
    a_q <- imported$qsig$a; b_q <- imported$qsig$b; kappa <- imported$qsig$E_inv_sigma
    seq.sigma <- imported$qsig$E_sigma
    stopifnot(iter == 0L, stable_count == 0L, !converged, length(elbo_trace) == 0L)
  })
  gate <- quote({
    stopifnot(identical(Sys.getenv('R154_PROJECT_MODE'), 'pilot'))
    r525_gate_bound(X, y, max_iter)
  })
  body_items <- append(body_items, list(restore), after = for_index - 1L)
  body_items <- append(body_items, list(gate), after = 1L)
  projected <- original; body(projected) <- as.call(body_items)
  child <- new.env(parent = environment(original))
  child$r525_gate_bound <- function(X, y, max_iter) r525_closed_data_limits(ctx, X, y, max_iter)
  child$r525_restore_bound <- function(...) r525_validate_state(..., ns = ns, ctx = ctx)
  child$r525_checkpoint_bound <- function(frame) r525_checkpoint(frame, ctx, output)
  environment(projected) <- child
  attr(projected, 'original_stock_body_sha256') <- digest::digest(body(original), algo = 'sha256')
  projected
}
