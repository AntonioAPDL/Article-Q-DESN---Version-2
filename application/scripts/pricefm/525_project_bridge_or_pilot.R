#!/usr/bin/env Rscript
# Root-admitted bridge or one new initialization attempt; no implicit execution.
args <- commandArgs(TRUE); stopifnot(length(args) == 6L)
mode <- args[[1L]]; root <- normalizePath(args[[2L]], mustWork = TRUE)
manifest_path <- normalizePath(args[[3L]], mustWork = TRUE)
grant_path <- normalizePath(args[[4L]], mustWork = TRUE); grant_sha <- args[[5L]]
output <- normalizePath(args[[6L]], mustWork = TRUE)
hash <- function(p) digest::digest(p, file = TRUE, algo = 'sha256')
stopifnot(identical(Sys.getenv('R154_PROJECT_ROOT_ADMITTED'), '1'),
  identical(hash(grant_path), grant_sha), mode %in% c('bridge', 'pilot'))
grant <- jsonlite::read_json(grant_path, simplifyVector = TRUE)
admission_pin <- list(path = Sys.getenv('R154_PROJECT_ADMISSION_PATH'), sha256 = Sys.getenv('R154_PROJECT_ADMISSION_SHA256'))
runtime_pin <- list(path = Sys.getenv('R154_PROJECT_RUNTIME_PATH'), sha256 = Sys.getenv('R154_PROJECT_RUNTIME_SHA256'))
stopifnot(identical(hash(admission_pin$path), admission_pin$sha256),
  identical(hash(runtime_pin$path), runtime_pin$sha256))
expected_status <- if (mode == 'bridge') 'ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY' else
  'ROOT_ADMITTED_NEW_INITIALIZATION_PILOT_ONLY'
stopifnot(identical(grant$status, expected_status), identical(grant$mode, mode),
  identical(hash(manifest_path), grant$manifest_sha256),
  identical(Sys.getenv('R154_PROJECT_MODE'), mode),
  identical(grant$authorizes_production_acceptance, FALSE),
  grant$max_iter == if (mode == 'bridge') 0L else 300L,
  grant$new_attempt_index == 1L)
for (i in seq_len(nrow(grant$source_bindings)))
  stopifnot(identical(hash(grant$source_bindings$path[[i]]), grant$source_bindings$sha256[[i]]))
global <- jsonlite::read_json(grant$global_contract$path, simplifyVector = TRUE)
stopifnot(identical(hash(grant$global_contract$path), grant$global_contract$sha256),
  global$max_new_numerical == 1L,
  identical(Sys.readlink(file.path('/proc/self/fd', Sys.getenv('R154_GLOBAL_PERMIT_LOCK_FD'))),
    file.path(global$lock_dir, 'muscat_cpu30.lock')))
status <- readLines('/proc/self/status')
stopifnot(identical(trimws(sub('Cpus_allowed_list:', '', status[startsWith(status, 'Cpus_allowed_list:')])), '30'))
manifest <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
stopifnot(identical(hash(manifest$original_manifest$path), manifest$original_manifest$sha256))
original <- jsonlite::read_json(manifest$original_manifest$path, simplifyVector = FALSE)
target <- Filter(function(x) identical(x$name, grant$target_name), original$targets)
stopifnot(length(target) == 1L); target <- target[[1L]]
execution <- manifest$execution[[grant$target_name]]; stopifnot(!is.null(execution))
resolve <- function(p) if (!is.null(execution$aliases[[p]])) execution$aliases[[p]] else p
for (item in target$bindings) stopifnot(identical(hash(resolve(item$path)), item$sha256))
c <- target$contract
for (key in c('design_dir','output_dir','parent_dir','cran_adapter','cran_manifest','fixedpoint_helper'))
  c[[key]] <- resolve(c[[key]])
design <- jsonlite::read_json(file.path(c$design_dir, 'design.json'), simplifyVector = TRUE)
dt <- jsonlite::read_json(file.path(c$design_dir, 'terminal.json'), simplifyVector = TRUE)
for (name in names(dt$files)) stopifnot(identical(hash(file.path(c$design_dir, name)), dt$files[[name]]))
source(c$fixedpoint_helper)
source(file.path(root, 'application/R/525_project_fullstate_consumer.R'))
ns <- r129_namespace(c$cran_library); stock <- get('.run_static_dqlm_cavi', ns)
stopifnot(identical(digest::digest(body(stock), algo = 'sha256'), grant$expected_stock_body_sha256))
ctx <- list2env(list(target_name = target$name, n = target$n, p = target$p,
  origin = 'sealed_real_target_project_consumer',
  tau = target$tau, tau0 = target$tau0, source = grant$source,
  original_manifest_sha256 = manifest$original_manifest$sha256,
  posterior_target_sha256 = target$posterior_target_sha256,
  units = 'original_design_and_response', prior = original$scope$prior,
  original_failed = target$bindings, checkpoint_entries = list(),
  disk_bytes = grant$disk_GiB * 1024^3,
  data_references = list(X = list(path = file.path(c$design_dir, 'X.bin'), sha256 = dt$files[['X.bin']]),
    y = list(path = file.path(c$design_dir, 'y.bin'), sha256 = dt$files[['y.bin']]))), parent = emptyenv())
read64 <- function(path, n) {
  stopifnot(file.info(path)$size == 8 * n)
  con <- file(path, 'rb'); on.exit(close(con))
  x <- readBin(con, double(), n, size = 8L, endian = 'little')
  stopifnot(length(x) == n, all(is.finite(x))); x
}
write_json <- function(name, value) {
  text <- jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = 'null', na = 'null')
  con <- file(file.path(output, name), 'wx'); on.exit(close(con)); writeLines(text, con)
}
save_state <- function(name, value) {
  path <- file.path(output, name); stopifnot(!file.exists(path)); saveRDS(value, path, compress = FALSE)
  list(path = path, sha256 = hash(path))
}
strip_certificate <- function(cert) {
  cert[c('reconstructed_rhs_state','latent_state','beta_covariance','prior_center')] <- NULL
  cert$limits <- as.list(cert$limits); cert
}
X <- matrix(read64(ctx$data_references$X$path, ctx$n * ctx$p), ctx$n, byrow = TRUE)
y <- read64(ctx$data_references$y$path, ctx$n)
r525_closed_data_limits(ctx, X, y)
prior <- r129_prior(ns, ctx$p, ctx$tau0)
if (mode == 'bridge') {
  terminal <- jsonlite::read_json(file.path(c$output_dir, 'terminal.json'), simplifyVector = TRUE)
  old_cert <- jsonlite::read_json(file.path(c$output_dir, 'fixedpoint_certificate.json'), simplifyVector = TRUE)
  m <- read64(file.path(c$output_dir, 'beta_mean.bin'), ctx$p)
  V <- matrix(read64(file.path(c$output_dir, 'beta_cov.bin'), ctx$p^2), ctx$p, byrow = TRUE)
  V <- .5 * (V + t(V))  # Same source-equivalent convention as original r129.
  cert <- r129_certificate(ns, X, y, m, V, terminal$sigma, ctx$tau, ctx$tau0,
    unlist(c$certificate_limits), max_rhs_iter = c$max_rhs_iter)
  stopifnot(all(vapply(names(cert$measures), function(k)
    identical(as.numeric(cert$measures[[k]]), as.numeric(old_cert$measures[[k]])), logical(1))),
    cert$raw_reconstructed_elbo == old_cert$raw_reconstructed_elbo,
    cert$raw_next_elbo == old_cert$raw_next_elbo,
    all(vapply(names(cert$rhs_reconstruction), function(k)
      cert$rhs_reconstruction[[k]] == old_cert$rhs_reconstruction[[k]], logical(1))),
    cert$rhs_reconstruction$unit_converged, cert$rhs_reconstruction$dispersed_converged)
  current <- r129_elbo(ns, prior, cert$reconstructed_rhs_state, m, V, terminal$sigma, y, X, ctx$tau)
  chi <- pmax((current$kappa / current$B) * current$second, 1e-12)
  psi <- max(current$kappa * (2 + current$A^2 / current$B), 1e-12)
  factors <- list(schema = 'r154_project_full_factors_v1', origin = 'sealed_real_target_project_consumer',
    kind = 'conditional_reconstruction_new_initialization', target_key = ctx$posterior_target_sha256,
    qbeta = list(m = m, V = V),
    qv = list(chi = chi, psi = psi, E_v = current$nu, E_inv_v = current$ell,
      E_log_v = get('.dqlm_gig_elog', ns)(.5, chi, psi)),
    qsig = list(a = current$a, b = current$b, E_sigma = terminal$sigma,
      E_inv_sigma = current$kappa, E_log_sigma = log(current$b) - digamma(current$a)),
    rhs_state = cert$reconstructed_rhs_state, prior_controls = prior$controls,
    source_provenance = list(source = ctx$source, data_references = ctx$data_references,
      original_failed_bindings = target$bindings, prior_attempt_iterations = terminal$iterations,
      conditional_RHS_counts_not_AL_sweeps = cert$rhs_reconstruction,
      exact_optimizer_resume = FALSE, old_missing_factors_recovered = FALSE))
  checked <- r525_validate_state(factors, X, y, ctx$tau, prior, rep(0, ctx$p), diag(1e6, ctx$p), 1, 1, ns, ctx)
  stopifnot(identical(checked, factors))
  explicit <- r525_explicit_factor_elbo(ns, prior, factors, X, y, ctx$tau, ctx)
  bound <- 128 * .Machine$double.eps * max(1, sum(abs(unlist(explicit$terms))))
  stopifnot(abs(explicit$objective - current$elbo) <= bound)
  state_pin <- save_state('full_state.rds', factors)
  write_json('baseline_certificate.json', strip_certificate(cert))
  write_json('bridge_validation.json', list(schema = 'r154_conditional_state_bridge_v1',
    status = 'VERIFIED_ZERO_OPTIMIZER_CONDITIONAL_STATE_BRIDGE', target_name = ctx$target_name,
    posterior_target_sha256 = ctx$posterior_target_sha256, source = ctx$source,
    units = ctx$units, prior = ctx$prior, optimizer_updates = 0L,
    full_state_factors_verified = TRUE, explicit_factor_elbo_verified = TRUE,
    original_seven_certificate_computed = TRUE, rhs_unit_and_dispersed_verified = TRUE,
    source_recipe_reproduced = TRUE, factor_state = state_pin, data_references = ctx$data_references,
    baseline_certificate_pin = list(path = file.path(output, 'baseline_certificate.json'),
      sha256 = hash(file.path(output, 'baseline_certificate.json'))),
    explicit_factor_objective = explicit, original_conditional_objective = current$elbo,
    objective_difference = explicit$objective - current$elbo,
    verification_bound_not_a_production_gate = bound,
    original_failed_state_modified = FALSE, exact_optimizer_resume = FALSE,
    production_acceptance_authority = FALSE))
} else {
  stopifnot(identical(hash(grant$bridge_pin$path), grant$bridge_pin$sha256))
  bridge <- jsonlite::read_json(grant$bridge_pin$path, simplifyVector = TRUE)
  stopifnot(identical(bridge$target_name, ctx$target_name), identical(bridge$source, grant$source),
    bridge$optimizer_updates == 0L, bridge$full_state_factors_verified,
    bridge$explicit_factor_elbo_verified, bridge$source_recipe_reproduced,
    identical(hash(bridge$factor_state$path), bridge$factor_state$sha256))
  factors <- readRDS(bridge$factor_state$path)
  stopifnot(identical(factors$kind, 'conditional_reconstruction_new_initialization'))
  r525_validate_state(factors, X, y, ctx$tau, prior, rep(0, ctx$p), diag(1e6, ctx$p), 1, 1, ns, ctx)
  stopifnot(dir.create(file.path(output, 'checkpoints')))
  engine <- r525_make_engine(ns, ctx, output); set.seed(c$seed)
  fit <- engine(y, X, ctx$tau, max_iter = 300L, tol = c$tol,
    b0 = rep(0, ctx$p), V0 = diag(1e6, ctx$p), beta_prior_obj = prior,
    a_sigma = 1, b_sigma = 1, init = list(full_state = factors),
    n.samp = c$n_samp, verbose = FALSE)
  trace <- as.data.frame(fit$diagnostics$vb_trace)
  sigma <- as.numeric(fit$qsig$E_sigma); m <- as.numeric(fit$qbeta$m); V <- as.matrix(fit$qbeta$V)
  finite <- length(m) == ctx$p && all(is.finite(m)) && all(is.finite(V)) &&
    all(diag(V) > 0) && is.finite(sigma) && sigma > 0 && nrow(trace) > 0
  stopifnot(finite, fit$iter >= 1L, fit$iter <= 300L, length(ctx$checkpoint_entries) == fit$iter)
  # Always compute all original seven measures, even when raw formal is TRUE.
  cert <- r129_certificate(ns, X, y, m, V, sigma, ctx$tau, ctx$tau0,
    unlist(c$certificate_limits), max_rhs_iter = c$max_rhs_iter)
  stopifnot(length(cert$measures) == 7L)
  accepted <- finite && (isTRUE(fit$converged) || isTRUE(cert$certified))
  write64 <- function(name, value) {
    con <- file(file.path(output, name), 'wb'); on.exit(close(con))
    writeBin(as.double(value), con, size = 8L, endian = 'little')
  }
  write64('beta_mean.bin', m); write64('beta_cov.bin', t(V))
  utils::write.csv(trace, file.path(output, 'vb_trace.csv'), row.names = FALSE)
  save_state('final_state.rds', list(qbeta = fit$qbeta, qv = fit$qv, qsig = fit$qsig,
    beta_prior = fit$beta_prior, diagnostics = fit$diagnostics, misc = fit$misc,
    data_references = ctx$data_references, source = ctx$source,
    RNG_after_stock_sampling = get('.Random.seed', .GlobalEnv),
    posterior_draws_retained = FALSE, stock_sampling_executed = TRUE,
    exact_optimizer_resume_supported = FALSE))
  save_state('independent_certificate_full_state.rds', cert)
  write_json('checkpoint_index.json', list(schema = 'r154_fullstate_checkpoint_index_v1',
    target_name = ctx$target_name, posterior_target_sha256 = ctx$posterior_target_sha256,
    n = ctx$n, p = ctx$p, tau = ctx$tau, tau0 = ctx$tau0,
    source = ctx$source, data_references = ctx$data_references, checkpoints = ctx$checkpoint_entries))
  write_json('terminal_core.json', list(schema = 'r154_project_consumer_candidate_v1',
    record_kind = 'pilot_candidate_no_automatic_release', origin = 'sealed_real_target_project_consumer',
    target_name = ctx$target_name, posterior_target_sha256 = ctx$posterior_target_sha256,
    n = ctx$n, p = ctx$p, tau = ctx$tau, tau0 = ctx$tau0,
    original_manifest_sha256 = ctx$original_manifest_sha256,
    source = ctx$source, units = ctx$units, prior = ctx$prior,
    initializer = list(kind = 'conditional_reconstruction_new_initialization', bridge = grant$bridge_pin,
      exact_optimizer_resume = FALSE, prior_center_from_initializer = FALSE),
    max_iter = 300L, new_attempt_index = 1L, maximum_new_attempts = 1L,
    prior_attempt_iterations = 300L, completed_sweeps = fit$iter,
    cumulative_update_history = list(previous_failed_attempt_sweeps = 300L,
      this_separate_attempt_completed_sweeps = fit$iter, single_fit_cap = 300L,
      old_attempt_resumed = FALSE),
    finite_core = finite, formal_converged = isTRUE(fit$converged),
    raw_stock_convergence = fit$diagnostics$convergence,
    independent_certificate = strip_certificate(cert), all_seven_certificate_computed = TRUE,
    computationally_certified = accepted,
    checkpoint_index = list(path = file.path(output, 'checkpoint_index.json'),
      sha256 = hash(file.path(output, 'checkpoint_index.json'))),
    original_failed = target$bindings, admission_pin = admission_pin,
    runtime_pin = runtime_pin,
    sigma = sigma, seed = c$seed, test_opened = FALSE, prior_center_from_initializer = FALSE,
    acceptance_logic = 'finite AND (formal OR independent)',
    old_completed_artifacts_modified = FALSE,
    production_parent_or_original_failed_state_modified = FALSE,
    automatic_dependant_release = FALSE, scope_expansion_to_other_five = FALSE))
}
cat('New source stage returned; candidate only, no automatic release\n')
