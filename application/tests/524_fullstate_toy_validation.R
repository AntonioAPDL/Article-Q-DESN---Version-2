#!/usr/bin/env Rscript
# Prepared validation only. No optimizer runs before an explicit root toy grant.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 4L)
root <- normalizePath(args[[1L]], mustWork = TRUE)
grant_path <- normalizePath(args[[2L]], mustWork = TRUE)
grant_sha <- args[[3L]]; output <- args[[4L]]
hash <- function(p) digest::digest(p, file = TRUE, algo = 'sha256')
stopifnot(identical(Sys.getenv('R154_TOY_ROOT_ADMITTED'), '1'),
  identical(hash(grant_path), grant_sha), !file.exists(output))
grant <- jsonlite::read_json(grant_path, simplifyVector = TRUE)
stopifnot(identical(grant$status, 'ROOT_ADMITTED_TOY_FULLSTATE_VALIDATION_ONLY'),
  identical(grant$authorizes_toy_optimizer, TRUE),
  identical(grant$authorizes_production_fits, FALSE),
  identical(grant$authorizes_production_acceptance, FALSE),
  grant$maximum_CPU_seconds > 0, grant$maximum_CPU_seconds <= 300,
  grant$maximum_cases == 8L, grant$maximum_n == 128L, grant$maximum_p == 32L,
  grant$maximum_optimizer_invocations == 8L,
  grant$maximum_total_optimizer_iterations == 30L)
stopifnot(as.numeric(Sys.time()) < grant$stage_deadline_epoch,
  Sys.time() < as.POSIXct(substr(grant$expires_UTC, 1L, 19L),
    format = '%Y-%m-%dT%H:%M:%S', tz = 'UTC'),
  as.numeric(as.POSIXct(substr(grant$expires_UTC, 1L, 19L),
    format = '%Y-%m-%dT%H:%M:%S', tz = 'UTC')) <= grant$stage_deadline_epoch)
for (row in seq_len(nrow(grant$source_bindings)))
  stopifnot(identical(hash(grant$source_bindings$path[[row]]), grant$source_bindings$sha256[[row]]))
status <- readLines('/proc/self/status')
stopifnot(identical(trimws(sub('Cpus_allowed_list:', '',
  status[startsWith(status, 'Cpus_allowed_list:')])), '30'))
lock_fd <- Sys.getenv('R154_GLOBAL_PERMIT_LOCK_FD')
global <- jsonlite::read_json(grant$global_contract$path, simplifyVector = TRUE)
stopifnot(identical(hash(grant$global_contract$path), grant$global_contract$sha256),
  global$max_new_numerical == 1L,
  identical(Sys.readlink(file.path('/proc/self/fd', lock_fd)),
    file.path(global$lock_dir, 'muscat_cpu30.lock')))
source(file.path(root, 'application/R/pricefm_r129_al_fixedpoint_certificate.R'))
source(file.path(root, 'application/R/524_toy_fullstate_consumer.R'))
ns <- r129_namespace(grant$cran_library)
stock <- get('.run_static_dqlm_cavi', ns)
stock_body <- body(stock); consumer <- r524_make_toy_engine(ns)
stopifnot(identical(digest::digest(stock_body, algo = 'sha256'), grant$expected_stock_body_sha256))
optimizer_calls <- 0L; total_iterations <- 0L; cases <- list(); started <- proc.time()
run <- function(engine, X, y, tau, prior, seed, init = NULL, iterations = 4L) {
  optimizer_calls <<- optimizer_calls + 1L
  stopifnot(optimizer_calls <= 8L, iterations <= 30L)
  total_iterations <<- total_iterations + iterations
  stopifnot(total_iterations <= 30L)
  set.seed(seed)
  engine(y, X, tau, max_iter = iterations, tol = 1e-8,
    b0 = rep(0, ncol(X)), V0 = diag(1e6, ncol(X)), beta_prior_obj = prior,
    a_sigma = 1, b_sigma = 1, init = init, n.samp = 2L, verbose = FALSE)
}
science <- function(fit) fit[c('qbeta', 'qv', 'qsig', 'beta_prior', 'iter',
  'converged', 'misc', 'diagnostics')]
pair <- function(n, p, tau, seed, init = NULL) {
  set.seed(seed); X <- cbind(1, matrix(rnorm(n * (p - 1L)), n, p - 1L))
  attr(X, 'r524_origin') <- 'synthetic_toy'
  y <- as.numeric(X %*% seq(.05, .2, length.out = p) + rnorm(n, sd = .3))
  prior <- r129_prior(ns, p, .01)
  a <- run(stock, X, y, tau, prior, seed + 1L, init)
  b <- run(consumer, X, y, tau, prior, seed + 1L, init)
  stopifnot(identical(science(a), science(b)), identical(body(stock), stock_body))
  list(fit = a, X = X, y = y, tau = tau, prior = prior)
}
first <- pair(32L, 4L, .5, 52401L)
cases[['1_stock_default_pair']] <- list(pass = TRUE, exact_science_equal = TRUE,
  n = 32L, p = 4L, optimizer_calls = 2L, total_iterations = 8L)
second <- pair(64L, 8L, .9, 52402L, init = list(beta = rep(.1, 8L), sigma = .7))
cases[['2_stock_beta_sigma_pair']] <- list(pass = TRUE, exact_science_equal = TRUE,
  n = 64L, p = 8L, optimizer_calls = 2L, total_iterations = 8L)
s <- r524_snapshot(first$fit, first$prior)
roundtrip <- r524_validate_state(s, first$X, first$y, first$tau, first$prior,
  rep(0, 4L), diag(1e6, 4L), 1, 1, ns)
stopifnot(identical(roundtrip, s))
explicit <- r524_explicit_factor_elbo(ns, first$prior, s, first$X, first$y, first$tau)
stock_last <- tail(first$fit$misc$elbo, 1L)
stopifnot(abs(explicit$objective - stock_last) <= 1e-10 * max(1, abs(stock_last)))
cases[['3_zero_update_factor_import']] <- list(pass = TRUE,
  exact_all_factor_roundtrip = TRUE, explicit_minus_stock_objective = explicit$objective - stock_last,
  optimizer_calls = 0L)
one <- run(consumer, first$X, first$y, first$tau, first$prior, 52411L,
  init = list(full_state = s), iterations = 1L)
uninterrupted <- run(stock, first$X, first$y, first$tau, first$prior,
  52402L, iterations = 5L)
factors <- function(f) list(qbeta = f$qbeta, qv = f$qv, qsig = f$qsig,
  rhs = f$beta_prior$state)
stopifnot(identical(factors(one), factors(uninterrupted)))
independent <- r524_independent_one_block(ns, first$prior, s, first$X, first$y, first$tau)
one_state <- r524_snapshot(one, first$prior)
relative <- function(a, b) max(abs(a - b)) / max(1, max(abs(b)))
errors <- c(beta = relative(one_state$qbeta$m, independent$state$qbeta$m),
  covariance = relative(one_state$qbeta$V, independent$state$qbeta$V),
  sigma_rate = relative(one_state$qsig$b, independent$state$qsig$b),
  latent_chi = relative(one_state$qv$chi, independent$state$qv$chi),
  objective = abs(tail(one$misc$elbo, 1L) - independent$objective$objective) /
    max(1, abs(independent$objective$objective)))
rhs_keys <- c('a_lambda', 'b_lambda', 'a_nu', 'b_nu', 'a_tau', 'b_tau',
  'a_xi', 'b_xi', 'a_zeta', 'b_zeta')
errors <- c(errors, rhs_factors = relative(unlist(one_state$rhs_state[rhs_keys]),
  unlist(independent$state$rhs_state[rhs_keys])))
stopifnot(all(is.finite(errors)), all(errors <= 1e-10),
  one$iter == 1L, one$diagnostics$convergence$stable_count <= 1L)
cases[['4_independent_one_block']] <- list(pass = TRUE, errors = as.list(errors),
  precision_condition = independent$precision_condition, optimizer_calls = 2L,
  full_factor_import_plus_one_equals_uninterrupted_fifth_sweep = TRUE,
  outer_stopping_bookkeeping_is_new_not_resume = TRUE,
  original_prior_closure_shared = TRUE)
mean_sigma <- s$qsig$E_sigma; a <- s$qsig$a
stock_initial_mean <- a * mean_sigma / (a - 1)
stopifnot(stock_initial_mean > mean_sigma,
  abs((a - 1) * mean_sigma - s$qsig$b) <= 1e-12 * max(1, abs(s$qsig$b)))
cases[['5_sigma_mean_semantics']] <- list(pass = TRUE,
  stock_relative_mean_change = stock_initial_mean / mean_sigma - 1,
  sigma_prior_remains_IG_1_1 = TRUE, optimizer_calls = 0L)
reject <- function(state) inherits(try(r524_validate_state(state, first$X,
  first$y, first$tau, first$prior, rep(0, 4L), diag(1e6, 4L), 1, 1, ns), silent = TRUE), 'try-error')
bad <- s; bad$qsig$b <- -1; stopifnot(reject(bad))
bad <- s; bad$target_key <- 'changed'; stopifnot(reject(bad))
bad <- s; bad$formal_converged <- TRUE; stopifnot(reject(bad))
bad <- s; bad$qv <- NULL; stopifnot(reject(bad))
big <- matrix(1, 129L, 4L); attr(big, 'r524_origin') <- 'synthetic_toy'
stopifnot(inherits(try(r524_toy_limits(big, rep(0, 129L)), silent = TRUE), 'try-error'))
cases[['6_negative_state_and_production_dimension']] <- list(pass = TRUE,
  rejected = c('negative_rate', 'wrong_target', 'inherited_formal_flag', 'missing_latents', 'n129'), optimizer_calls = 0L)
different <- s; different$kind <- 'synthetic_valid_factor_product_new_initialization'
different$qv$chi <- different$qv$chi * 1.2; different$qv$psi <- different$qv$psi * .8
different$qv$E_inv_v <- sqrt(different$qv$psi / different$qv$chi)
different$qv$E_v <- sqrt(different$qv$chi / different$qv$psi) *
  (1 + 1 / sqrt(different$qv$chi * different$qv$psi))
different$qv$E_log_v <- get('.dqlm_gig_elog', ns)(.5, different$qv$chi, different$qv$psi)
accepted <- r524_validate_state(different, first$X, first$y, first$tau,
  first$prior, rep(0, 4L), diag(1e6, 4L), 1, 1, ns)
stopifnot(identical(accepted, different), !identical(accepted$qv, s$qv))
cases[['7_latent_own_parameters_preserved']] <- list(pass = TRUE,
  no_reconditioning_on_current_sigma = TRUE, optimizer_calls = 0L)
stress <- pair(128L, 32L, .1, 52403L)
cases[['8_stress_stock_default_pair']] <- list(pass = TRUE,
  exact_science_equal = TRUE, n = 128L, p = 32L, optimizer_calls = 2L,
  total_iterations = 8L)
stopifnot(length(cases) == 8L, optimizer_calls == 8L, total_iterations == 30L,
  identical(body(stock), stock_body))
elapsed <- proc.time() - started
result <- list(status = 'PASS_TOY_ONLY_CONSUMER_VALIDATION',
  record_kind = 'synthetic_toy_only_no_production_acceptance_authority',
  cases = cases, case_count = length(cases), toy_optimizer_invocations = optimizer_calls,
  total_toy_optimizer_iterations = total_iterations, maximum_n = 128L, maximum_p = 32L,
  original_namespace_function_unchanged = TRUE,
  stock_body_sha256 = digest::digest(stock_body, algo = 'sha256'),
  process_CPU_seconds = unname(sum(elapsed[c('user.self', 'sys.self')])),
  wall_seconds = unname(elapsed[['elapsed']]), production_fit_invocations = 0L,
  production_passflags_written = 0L, formal_OR_independent_production_rule_changed = FALSE,
  continuation_will_certify_claimed = FALSE)
encoded <- jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, digits = 17)
con <- file(output, open = 'wx'); on.exit(close(con)); writeLines(encoded, con)
cat('Toy-only validation returned; no production fit or acceptance authority\n')
