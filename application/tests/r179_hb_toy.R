r179_hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
r179_verify <- function(pin) {
  stopifnot(setequal(names(pin), c('path','sha256')),
    identical(r179_hash(pin$path), pin$sha256))
  pin$path
}
r179_binding_map <- function(x) {
  if (is.data.frame(x)) setNames(as.character(x$sha256), as.character(x$path)) else
    setNames(vapply(x, function(p) p$sha256, character(1)), vapply(x, function(p) p$path, character(1)))
}
r179_job_gate <- function(grant, role) {
  stopifnot(identical(grant$schema, 'pricefm_hb_scientific_stage_grant_v1'),
    identical(grant$role, role), identical(grant$job_id, Sys.getenv('SLURM_JOB_ID')),
    identical(grant$node, Sys.getenv('SLURMD_NODENAME')),
    !grepl('login|head|submit', grant$node, ignore.case = TRUE),
    identical(Sys.getenv('SLURM_CPUS_PER_TASK'), '1'), grant$memory_MiB == 8192,
    grant$max_new_numerical == 1L, grant$attempt_index == 1L,
    identical(grant$old_claims_reused, FALSE), identical(grant$old_costs_refunded, FALSE),
    identical(grant$authorizes_production_acceptance, FALSE))
  affinity <- trimws(sub('Cpus_allowed_list:', '',
    readLines('/proc/self/status')[startsWith(readLines('/proc/self/status'), 'Cpus_allowed_list:')]))
  stopifnot(length(grant$affinity) == 1L, identical(affinity, as.character(grant$affinity[[1L]])))
  expiry <- as.numeric(as.POSIXct(substr(grant$expires_UTC, 1L, 19L),
    format = '%Y-%m-%dT%H:%M:%S', tz = 'UTC'))
  stopifnot(is.finite(expiry), as.numeric(Sys.time()) < expiry,
    expiry <= grant$stage_deadline_epoch)
  pool <- jsonlite::read_json(r179_verify(grant$global_contract), simplifyVector = FALSE)
  stopifnot(identical(pool$schema, 'r179_hb_scientific_job_contract_v1'),
    identical(pool$job_id, grant$job_id), identical(pool$node, grant$node),
    pool$max_new_numerical == 1L, grant$stage_deadline_epoch <= pool$expires_epoch)
  fd <- Sys.getenv('R154_GLOBAL_PERMIT_LOCK_FD')
  stopifnot(grepl('^[0-9]+$', fd),
    identical(Sys.readlink(file.path('/proc/self/fd',fd)), pool$resource_lock),
    any(grepl('FLOCK.*WRITE',readLines(file.path('/proc/self/fdinfo',fd)))))
  review <- jsonlite::read_json(r179_verify(grant$source_review), simplifyVector = FALSE)
  stopifnot(identical(review$status, 'PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'),
    identical(review$execution_adapter_source, grant$execution_adapter_source),
    identical(review$job_id, grant$job_id), identical(review$node, grant$node),
    identical(review$role, grant$role), identical(review$scope_id, grant$scope_id),
    identical(sort(r179_binding_map(review$source_bindings)), sort(r179_binding_map(grant$source_bindings))))
  boundary <- jsonlite::read_json(r179_verify(grant$scientific_boundary_qualification), simplifyVector = FALSE)
  boundary_guard <- jsonlite::read_json(r179_verify(boundary$owned_guard), simplifyVector = FALSE)
  stopifnot(identical(boundary$status, 'PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'),
    identical(boundary$original_guard_source_preserved, TRUE),
    identical(boundary_guard$schema, 'r157_traced_bootstrap_guard_receipt_v1'),
    identical(boundary_guard$status, 'EXITED'), boundary_guard$returncode == 0,
    identical(boundary_guard$reaped, TRUE), identical(boundary_guard$drained, TRUE),
    identical(boundary_guard$all_newborns_kernel_traced_before_execution, TRUE),
    identical(boundary_guard$postbootstrap_TSYNC_scientific_fork_denial, TRUE),
    identical(boundary_guard$scientific_target_access_handshake, TRUE),
    identical(boundary_guard$CPU_accounting_complete, TRUE),
    length(boundary_guard$remaining_owned_lifetimes) == 0L,
    identical(Sys.getenv('R179_CURRENT_TSYNC_ACK_REQUIRED'), '1'))
  invisible(list(pool=pool,expiry=expiry))
}
# Versioned HB authority prefix; scientific suffix is byte-identical.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 4L)
root <- normalizePath(args[[1L]], mustWork = TRUE)
grant_path <- normalizePath(args[[2L]], mustWork = TRUE)
grant_sha <- args[[3L]]; output <- args[[4L]]; stopifnot(startsWith(output, '/'))
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
pin <- function(path) list(path = normalizePath(path, mustWork = TRUE), sha256 = hash(path))
verify <- function(value) { r179_verify(value) }
stopifnot(identical(Sys.getenv('R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED'), '1'),
  identical(hash(grant_path),grant_sha), !file.exists(output))
grant <- jsonlite::read_json(grant_path, simplifyVector = FALSE)
checked_job <- r179_job_gate(grant,'TOY_PARITY')
stopifnot(identical(grant$status,'ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY'),
  identical(grant$authorizes_toy_optimizer,TRUE), identical(grant$authorizes_production_fits,FALSE),
  grant$maximum_optimizer_invocations == 8L, grant$maximum_total_optimizer_iterations == 30L,
  grant$maximum_n == 128L, grant$maximum_p == 32L,
  grant$maximum_CPU_seconds > 0, grant$maximum_CPU_seconds <= 300,
  grant$memory_GiB == 8, grant$cores == 1)
source_id <- grant$source
stopifnot(identical(source_id$kind,'R154_project_fullstate_consumer_pinned_CRAN111'))
expiry <- checked_job$expiry; pool <- checked_job$pool
for (binding in grant$source_bindings) verify(binding)
required <- file.path(root, c('application/R/pricefm_r129_al_fixedpoint_certificate.R',
  'application/R/524_toy_fullstate_consumer.R', 'application/R/525_project_fullstate_consumer.R'))
stopifnot(all(required %in% names(r179_binding_map(grant$source_bindings))),
  identical(pin(grant$entrypoint$path), grant$entrypoint),
  grant$entrypoint$path %in% names(r179_binding_map(grant$source_bindings)))
runtime <- jsonlite::read_json(verify(grant$actual_R_runtime_binding),simplifyVector=FALSE)
stopifnot(identical(normalizePath(Sys.readlink('/proc/self/exe')),normalizePath(runtime$actual_executable)),
  identical(hash(runtime$actual_executable),runtime$actual_executable_sha256),
  identical(hash(runtime$Rscript),runtime$Rscript_sha256),
  identical(normalizePath(grant$cran_library),normalizePath(dirname(runtime$package_path))))
source(file.path(root, 'application/R/pricefm_r129_al_fixedpoint_certificate.R'))
source(file.path(root, 'application/R/524_toy_fullstate_consumer.R'))
source(file.path(root, 'application/R/525_project_fullstate_consumer.R'))
production_gate_body <- body(r525_closed_data_limits)
ns <- r129_namespace(grant$cran_library)
stock <- get('.run_static_dqlm_cavi', ns); stock_body <- body(stock)
stopifnot(identical(digest::digest(stock_body, algo = 'sha256'), grant$expected_stock_body_sha256))
stopifnot(dir.create(output), dir.create(file.path(output, 'synthetic_data')))
optimizer_calls <- 0L; total_sweeps <- 0L; cases <- list(); checkpoints <- list()
started <- proc.time(); Sys.setenv(R154_PROJECT_MODE = 'pilot')
science <- function(fit) fit[c('qbeta', 'qv', 'qsig', 'beta_prior', 'iter',
  'converged', 'misc', 'diagnostics')]
factors <- function(fit) list(qbeta = fit$qbeta, qv = fit$qv,
  qsig = fit$qsig, rhs = fit$beta_prior$state)
assert_time <- function() stopifnot(as.numeric(Sys.time()) < expiry)
run <- function(engine, X, y, tau, prior, seed, init = NULL, sweeps = 4L) {
  assert_time(); r524_toy_limits(X, y, sweeps)
  optimizer_calls <<- optimizer_calls + 1L; total_sweeps <<- total_sweeps + sweeps
  stopifnot(optimizer_calls <= 8L, total_sweeps <= 30L,
    prior$controls$freeze_tau_iters == 0L, prior$controls$freeze_tau_warmup_iters == 0L,
    identical(prior$controls$shrink_intercept, FALSE))
  set.seed(seed)
  fit <- engine(y, X, tau, max_iter = sweeps, tol = 1e-8,
    b0 = rep(0, ncol(X)), V0 = diag(1e6, ncol(X)), beta_prior_obj = prior,
    a_sigma = 1, b_sigma = 1, init = init, n.samp = 2L, verbose = FALSE)
  stopifnot(fit$iter == sweeps); assert_time(); fit
}
strip_projection <- function(code) {
  items <- as.list(code)
  inserted <- vapply(items, function(x) is.call(x) &&
    any(all.names(x) %in% c('r525_gate_bound', 'r525_restore_bound')), logical(1))
  stopifnot(sum(inserted) == 2L); items <- items[!inserted]
  index <- which(vapply(items, function(x) is.call(x) &&
    identical(x[[1L]], as.name('for')), logical(1)))
  stopifnot(length(index) == 1L)
  loop <- items[[index]]; inside <- as.list(loop[[4L]])
  checkpoint <- vapply(inside, identical, logical(1), quote(r525_checkpoint_bound(environment())))
  stopifnot(sum(checkpoint) == 1L)
  loop[[4L]] <- as.call(inside[!checkpoint]); items[[index]] <- loop
  as.call(items)
}
make_projection <- function(X, y, tau, prior, label) {
  folder <- file.path(output, label)
  stopifnot(dir.create(folder), dir.create(file.path(folder, 'checkpoints')))
  data_dir <- file.path(output, 'synthetic_data', label); stopifnot(dir.create(data_dir))
  writeBin(as.double(X), file.path(data_dir, 'X.bin'), size = 8L, endian = 'little')
  writeBin(as.double(y), file.path(data_dir, 'y.bin'), size = 8L, endian = 'little')
  ctx <- new.env(parent = emptyenv())
  ctx$origin <- 'synthetic_project_projection_fixture'
  ctx$target_name <- paste0('synthetic_NONCANDIDATE_', label)
  ctx$posterior_target_sha256 <- r524_target_key(X, y, tau, prior,
    rep(0, ncol(X)), diag(1e6, ncol(X)), 1, 1)
  ctx$source <- source_id; ctx$original_failed <- list()
  ctx$data_references <- list(X = pin(file.path(data_dir, 'X.bin')), y = pin(file.path(data_dir, 'y.bin')))
  ctx$disk_bytes <- 2 * 1024^3; ctx$checkpoint_entries <- list()
  # Production gate remains unchanged and cannot admit these small dimensions.
  stopifnot(inherits(try(r525_closed_data_limits(ctx, X, y), silent = TRUE), 'try-error'))
  projected <- r525_make_engine(ns, ctx, folder)
  original_projection <- body(projected)
  stopifnot(identical(strip_projection(original_projection), stock_body))
  items <- as.list(original_projection)
  restore_index <- which(vapply(items, function(x) is.call(x) &&
    identical(x[[1L]], as.name('{')) && length(x) > 1L &&
    identical(x[[2L]], quote(stopifnot(!is.null(init$full_state)))), logical(1)))
  stopifnot(length(restore_index) == 1L)
  exact_restore <- items[[restore_index]]
  # TEST COPY ONLY: permit original default stock initialization. Every restore
  # assignment is the unchanged production-generated AST nested in this guard.
  items[[restore_index]] <- as.call(list(as.name('if'), quote(!is.null(init$full_state)), exact_restore))
  body(projected) <- as.call(items)
  stopifnot(identical(body(projected)[[restore_index]][[3L]], exact_restore),
    identical(strip_projection(body(projected)), stock_body))
  child <- environment(projected)
  child$r525_gate_bound <- function(actual_X, actual_y, max_iter) {
    stopifnot(identical(Sys.getenv('R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED'), '1'),
      identical(hash(grant_path), grant_sha), identical(actual_X, X), identical(actual_y, y),
      identical(ctx$origin, 'synthetic_project_projection_fixture'),
      startsWith(ctx$target_name, 'synthetic_NONCANDIDATE_'))
    r524_toy_limits(actual_X, actual_y, max_iter); assert_time()
  }
  child$r525_restore_bound <- function(state, ...) {
    stopifnot(identical(state$schema, 'r154_project_full_factors_v1'),
      identical(state$origin, 'synthetic_project_projection_fixture'),
      identical(state$target_key, ctx$posterior_target_sha256),
      identical(state$source_provenance$source, source_id))
    toy <- state  # Change validation labels only, never any numerical factor.
    toy$schema <- 'r524_full_factors_new_initialization_v1'
    toy$origin <- 'synthetic_toy'; toy$kind <- 'full_stock_checkpoint_new_initialization'
    checked <- r524_validate_state(toy, ..., ns = ns)
    for (key in c('qbeta', 'qv', 'qsig', 'rhs_state', 'prior_controls'))
      stopifnot(identical(checked[[key]], state[[key]]))
    checked
  }
  list(engine = projected, ctx = ctx, folder = folder,
    production_projection_body_sha256 = digest::digest(original_projection, algo = 'sha256'))
}
verify_checkpoints <- function(projected, fit) {
  entries <- projected$ctx$checkpoint_entries
  stopifnot(length(entries) == fit$iter)
  for (i in seq_along(entries)) {
    entry <- entries[[i]]; stopifnot(entry$completed_sweep == i,
      identical(entry$contains_all_factors_and_schedules, TRUE))
    state <- readRDS(verify(entry$state_pin))
    disk_entry <- jsonlite::read_json(file.path(dirname(entry$state_pin$path), 'completed_evidence.json'))
    stopifnot(disk_entry$completed_sweep == i, identical(disk_entry$state_pin$sha256, entry$state_pin$sha256),
      identical(state$factors$origin, 'synthetic_project_projection_fixture'),
      identical(state$factors$target_key, projected$ctx$posterior_target_sha256),
      identical(state$data_references, projected$ctx$data_references),
      identical(state$source, source_id), state$optimizer$completed_sweep == i,
      length(state$optimizer$RNG_kind) >= 1L, length(state$optimizer$RNG_before_post_sampling) > 1L,
      is.list(state$optimizer$stock_controls), is.list(state$optimizer$step),
      identical(state$optimizer$resume_supported_by_this_adapter, FALSE),
      all(c('qbeta', 'qv', 'qsig', 'rhs_state', 'prior_controls') %in% names(state$factors)),
      all(c('stable_count', 'elbo_trace', 'seq_sigma', 'delta_beta', 'delta_sigma', 'delta_elbo') %in%
        names(state$optimizer)))
    verify(state$data_references$X); verify(state$data_references$y)
  }
  final <- readRDS(entries[[length(entries)]]$state_pin$path)$factors
  for (block in c('qbeta', 'qv', 'qsig')) for (key in names(fit[[block]]))
    stopifnot(identical(final[[block]][[key]], fit[[block]][[key]]))
  stopifnot(identical(final$rhs_state, fit$beta_prior$state))
  checkpoints[[length(checkpoints) + 1L]] <<- list(label = projected$ctx$target_name,
    count = length(entries), entries = entries,
    production_projection_body_sha256 = projected$production_projection_body_sha256)
  final
}
pair <- function(n, p, tau, seed, label, init = NULL) {
  set.seed(seed); X <- cbind(1, matrix(rnorm(n * (p - 1L)), n, p - 1L))
  attr(X, 'r524_origin') <- 'synthetic_toy'
  y <- as.numeric(X %*% seq(.05, .2, length.out = p) + rnorm(n, sd = .3))
  prior <- r129_prior(ns, p, .01); controls <- prior$controls
  projected <- make_projection(X, y, tau, prior, label)
  a <- run(stock, X, y, tau, prior, seed + 1L, init)
  b <- run(projected$engine, X, y, tau, prior, seed + 1L, init)
  stopifnot(identical(science(a), science(b)), identical(prior$controls, controls),
    identical(body(stock), stock_body))
  final <- verify_checkpoints(projected, b)
  cases[[label]] <<- list(pass = TRUE, exact_science_equal = TRUE, n = n, p = p,
    tau = tau, optimizer_invocations = 2L, requested_sweeps = 8L)
  list(fit = a, X = X, y = y, tau = tau, prior = prior, state = final)
}
first <- pair(32L, 4L, .5, 52501L, 'default_pair')
second <- pair(64L, 8L, .9, 52502L, 'beta_sigma_pair', init = list(beta = rep(.1, 8L), sigma = .7))
imported <- make_projection(first$X, first$y, first$tau, first$prior, 'checkpoint_import')
one <- run(imported$engine, first$X, first$y, first$tau, first$prior,
  52511L, init = list(full_state = first$state), sweeps = 1L)
invisible(verify_checkpoints(imported, one))
uninterrupted <- run(stock, first$X, first$y, first$tau, first$prior, 52502L, sweeps = 5L)
stopifnot(identical(factors(one), factors(uninterrupted)), one$iter == 1L,
  one$diagnostics$convergence$stable_count <= 1L)
cases$checkpoint_import <- list(pass = TRUE, all_factors_plus_one_equal_stock_fifth = TRUE,
  new_outer_history_not_exact_resume = TRUE, optimizer_invocations = 2L, requested_sweeps = 6L)
stress <- pair(128L, 32L, .1, 52503L, 'stress_default_pair')
stopifnot(optimizer_calls == 8L, total_sweeps == 30L, identical(body(stock), stock_body),
  identical(body(r525_closed_data_limits), production_gate_body))
elapsed <- proc.time() - started
result <- list(schema = 'r154_project_adapter_validation_core_v1',
  status = 'NUMERICAL_PASS_AWAIT_OWNED_GUARD_REAP_PROOF',
  record_kind = 'synthetic_project_projection_fixture_NONCANDIDATE', source = source_id,
  actual_R_runtime_binding = grant$actual_R_runtime_binding,
  root_grant_pin = pin(grant_path), toy_default_and_import_parity_pass = TRUE,
  checkpoint_all_factors_schedules_RNG_IO_verified = TRUE,
  stock_AST_exactly_preserved = TRUE, no_production_data_used = TRUE,
  production_gate_unchanged_and_rejects_synthetic = TRUE,
  toy_optimizer_invocations = optimizer_calls, total_toy_optimizer_iterations = total_sweeps,
  maximum_n = 128L, maximum_p = 32L, cases = cases, checkpoints = checkpoints,
  stock_body_sha256 = digest::digest(stock_body, algo = 'sha256'),
  process_CPU_seconds = unname(sum(elapsed[c('user.self', 'sys.self')])),
  production_fit_invocations = 0L, production_passflags_written = 0L,
  optimizer_resume_claimed = FALSE, continuation_will_certify_claimed = FALSE)
con <- file(file.path(output, 'validation_core.json'), 'wx')
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, digits = 17), con); close(con)
cat('Synthetic numerical core written; completed owned-guard proof still required\n')
