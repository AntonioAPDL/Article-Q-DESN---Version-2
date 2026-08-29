`%||%` <- function(x, y) if (is.null(x)) y else x

r66_as_vector <- function(x, mode = c("character", "numeric", "integer")) {
  mode <- match.arg(mode)
  value <- unlist(x %||% vector(mode, 0L), use.names = FALSE)
  switch(
    mode,
    character = as.character(value),
    numeric = as.numeric(value),
    integer = as.integer(value)
  )
}

r66_tau_key <- function(tau) {
  sub("\\.$", "", sub("0+$", "", sprintf("%.12f", as.numeric(tau))))
}

r66_tau_slug <- function(tau) {
  gsub("-", "m", gsub("\\.", "p", r66_tau_key(tau)))
}

r66_sha256 <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  output <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  if (!identical(as.integer(status), 0L) || !length(output)) {
    stop("Could not hash ", path, call. = FALSE)
  }
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

r66_atomic_path <- function(path) {
  paste0(path, ".tmp.", Sys.getpid())
}

r66_atomic_replace <- function(tmp, path) {
  if (!file.rename(tmp, path)) {
    if (file.exists(path)) unlink(path)
    if (!file.rename(tmp, path)) {
      unlink(tmp)
      stop("Atomic rename failed for ", path, call. = FALSE)
    }
  }
  invisible(path)
}

r66_atomic_save_rds <- function(object, path, compress = "gzip") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r66_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  saveRDS(object, tmp, compress = compress)
  r66_atomic_replace(tmp, path)
}

r66_atomic_write_csv <- function(frame, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r66_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  utils::write.csv(frame, tmp, row.names = FALSE)
  r66_atomic_replace(tmp, path)
}

r66_atomic_write_json <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r66_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  cat(jsonlite::toJSON(object, auto_unbox = TRUE, pretty = TRUE, null = "null"), file = tmp)
  cat("\n", file = tmp, append = TRUE)
  r66_atomic_replace(tmp, path)
}

r66_safe_sigma <- function(fit) {
  value <- fit$qsiggam$sigma_mean %||% fit$omega2$mean %||% NA_real_
  value <- as.numeric(value)[1L]
  if (!is.null(fit$omega2$mean) && is.null(fit$qsiggam$sigma_mean)) {
    value <- sqrt(max(value, .Machine$double.eps))
  }
  if (!is.finite(value) || value <= 0) NA_real_ else value
}

r66_safe_gamma <- function(fit) {
  value <- as.numeric(fit$qsiggam$gamma_mean %||% NA_real_)[1L]
  if (!is.finite(value)) NA_real_ else value
}

r66_make_init <- function(source_fit, n_features, gamma_zero = FALSE) {
  beta_m <- source_fit$qbeta$m %||% source_fit$beta$mean %||% NULL
  beta_V <- source_fit$qbeta$V %||% source_fit$beta$cov %||% NULL
  if (is.null(beta_m) || is.null(beta_V) || length(beta_m) != n_features ||
      !all(dim(as.matrix(beta_V)) == c(n_features, n_features)) ||
      any(!is.finite(beta_m)) || any(!is.finite(beta_V))) {
    stop("Warm-start source has an incompatible beta state.", call. = FALSE)
  }
  init <- list(beta_m = as.numeric(beta_m), beta_V = as.matrix(beta_V))
  components <- c("beta")
  if (!is.null(source_fit$beta_prior$state)) {
    init$beta_state <- source_fit$beta_prior$state
    components <- c(components, "beta_state")
  }
  sigma <- r66_safe_sigma(source_fit)
  if (is.finite(sigma)) {
    init$sigma <- sigma
    components <- c(components, "sigma")
  }
  if (isTRUE(gamma_zero)) {
    init$gamma <- 0
    components <- c(components, "gamma_zero")
  }
  list(init = init, components = components, sigma = sigma)
}

r66_make_sigmagam_control <- function(profile) {
  exdqlm::exal_make_vb_sigmagam_control(
    factorization = as.character(profile$factorization),
    structured_grid_size = as.integer(profile$structured_grid_size),
    structured_span_sd = as.numeric(profile$structured_span_sd),
    freeze_warmup_iters = as.integer(profile$freeze_warmup_iters),
    force_after_warmup = isTRUE(profile$force_after_warmup),
    postwarmup_damping = as.numeric(profile$postwarmup_damping),
    postwarmup_damping_iters = as.integer(profile$postwarmup_damping_iters),
    min_postwarmup_updates = as.integer(profile$min_postwarmup_updates)
  )
}

r66_make_vb_control <- function(qcfg, likelihood, profile) {
  args <- list(
    max_iter = as.integer(qcfg$max_iter),
    min_iter_elbo = as.integer(qcfg$min_iter_elbo),
    tol = as.numeric(qcfg$tol),
    tol_par = as.numeric(qcfg$tol_par),
    n_samp_xi = as.integer(qcfg$n_samp_xi),
    progress_every = 1000000L,
    verbose = FALSE,
    chunking = qcfg$chunking
  )
  if (identical(likelihood, "exal")) {
    args$sigmagam <- r66_make_sigmagam_control(profile)
  }
  do.call(exdqlm::exal_make_vb_control, args)
}

r66_fit_quantile <- function(X, y, tau, likelihood, rhs, qcfg, profile,
                             init, seed) {
  set.seed(as.integer(seed))
  beta_prior <- exdqlm::beta_prior("rhs_ns", rhs = rhs)
  control <- r66_make_vb_control(qcfg, likelihood, profile)
  started <- proc.time()[["elapsed"]]
  fit <- exdqlm::exal_ldvb_fit(
    y = y,
    X = X,
    p0 = as.numeric(tau),
    gamma_bounds = c(exdqlm:::L.fn(tau), exdqlm:::U.fn(tau)),
    likelihood_family = likelihood,
    al_fixed_gamma = 0,
    beta_prior_obj = beta_prior,
    prior_sigma = qcfg$prior_sigma,
    prior_gamma = qcfg$prior_gamma,
    vb_control = control,
    init = init
  )
  attr(fit, "r66_elapsed_seconds") <- as.numeric(proc.time()[["elapsed"]] - started)
  fit
}

r66_sigmagam_telemetry <- function(fit) {
  misc <- fit$misc %||% list()
  structured <- fit$qsiggam$structured %||% list()
  bounds <- as.numeric(misc$bounds %||% c(NA_real_, NA_real_))
  gamma <- r66_safe_gamma(fit)
  sigma <- r66_safe_sigma(fit)
  width <- if (length(bounds) == 2L) bounds[[2L]] - bounds[[1L]] else NA_real_
  boundary_margin <- if (is.finite(gamma) && is.finite(width) && width > 0) {
    min(gamma - bounds[[1L]], bounds[[2L]] - gamma) / width
  } else {
    NA_real_
  }
  list(
    factorization = as.character(fit$qsiggam$factorization %||% NA_character_),
    configured_factorization = as.character((misc$sigmagam %||% list())$factorization %||% NA_character_),
    update_count = as.integer(misc$sigmagam_update_count %||% 0L),
    postwarmup_update_count = as.integer(misc$sigmagam_postwarmup_update_count %||% 0L),
    required_postwarmup_updates = as.integer(misc$sigmagam_required_postwarmup_updates %||% 0L),
    first_active_iter = as.integer(misc$sigmagam_first_active_iter %||% NA_integer_),
    exact_commit_count = as.integer(misc$structured_exact_commit_count %||% 0L),
    moment_source = as.character(fit$qsiggam$moment_source %||% misc$structured_moment_source %||% NA_character_),
    optimizer_start_source = as.character(structured$optimizer_start_source %||% NA_character_),
    optimizer_used_fallback = isTRUE(structured$used_fallback),
    gamma = gamma,
    sigma = sigma,
    gamma_lower = if (length(bounds) == 2L) bounds[[1L]] else NA_real_,
    gamma_upper = if (length(bounds) == 2L) bounds[[2L]] else NA_real_,
    gamma_relative_boundary_margin = as.numeric(boundary_margin)
  )
}

r66_sigmagam_telemetry_pass <- function(fit, minimum_exact_commits = 5L,
                                         minimum_boundary_margin = 1e-6) {
  telemetry <- r66_sigmagam_telemetry(fit)
  identical(telemetry$factorization, "structured_qgamma_qsigma_given_gamma") &&
    identical(telemetry$configured_factorization, "structured") &&
    identical(telemetry$moment_source, "conditional_gig_exact") &&
    identical(telemetry$optimizer_start_source, "eta_start") &&
    !isTRUE(telemetry$optimizer_used_fallback) &&
    telemetry$postwarmup_update_count >= max(1L, telemetry$required_postwarmup_updates) &&
    telemetry$exact_commit_count >= as.integer(minimum_exact_commits) &&
    is.finite(telemetry$gamma) && is.finite(telemetry$sigma) && telemetry$sigma > 0 &&
    is.finite(telemetry$gamma_relative_boundary_margin) &&
    telemetry$gamma_relative_boundary_margin >= as.numeric(minimum_boundary_margin)
}

r66_method_row <- function(fit, method_id, likelihood, tau, n_train, n_features,
                            init_source, init_hash, package_head) {
  telemetry <- r66_sigmagam_telemetry(fit)
  data.frame(
    method_id = method_id,
    model_family = "independent_qdesn_static_readout",
    likelihood_family = likelihood,
    prior_family = "rhs_ns",
    tau = as.numeric(tau),
    inference_engine = "VB",
    posterior_approximation = if (identical(likelihood, "exal")) {
      "structured_qgamma_qsigma_given_gamma"
    } else {
      "al_variational"
    },
    data_target_approximation = FALSE,
    exact_chunking = TRUE,
    chunking_mode = "exact",
    converged = isTRUE(fit$converged),
    iter = as.integer(fit$iter %||% NA_integer_),
    train_seconds = as.numeric(attr(fit, "r66_elapsed_seconds") %||% fit$run.time %||% NA_real_),
    n_train = as.integer(n_train),
    n_features = as.integer(n_features),
    readout_mode = "shared_static_final_layer",
    init_source = init_source,
    init_sha256 = init_hash,
    package_head = package_head,
    sigmagam_factorization = telemetry$factorization,
    sigmagam_configured_factorization = telemetry$configured_factorization,
    sigmagam_update_count = telemetry$update_count,
    sigmagam_postwarmup_update_count = telemetry$postwarmup_update_count,
    sigmagam_required_postwarmup_updates = telemetry$required_postwarmup_updates,
    sigmagam_first_active_iter = telemetry$first_active_iter,
    sigmagam_exact_commit_count = telemetry$exact_commit_count,
    sigmagam_moment_source = telemetry$moment_source,
    sigmagam_optimizer_start_source = telemetry$optimizer_start_source,
    sigmagam_optimizer_used_fallback = telemetry$optimizer_used_fallback,
    sigmagam_gamma_relative_boundary_margin = telemetry$gamma_relative_boundary_margin,
    stringsAsFactors = FALSE
  )
}

r66_warm_row <- function(fit, method_id, likelihood, tau, init_source,
                          init_components, init_hash) {
  data.frame(
    method_id = method_id,
    likelihood_family = likelihood,
    tau = as.numeric(tau),
    init_source = init_source,
    init_components = paste(init_components, collapse = "+"),
    init_sha256 = init_hash,
    fallback_used = FALSE,
    converged = isTRUE(fit$converged),
    iter = as.integer(fit$iter %||% NA_integer_),
    stringsAsFactors = FALSE
  )
}

r66_parameter_row <- function(fit, method_id, likelihood, tau) {
  beta <- as.numeric(fit$qbeta$m %||% numeric())
  covariance <- as.matrix(fit$qbeta$V %||% matrix(numeric(), 0L, 0L))
  data.frame(
    method_id = method_id,
    likelihood_family = likelihood,
    tau = as.numeric(tau),
    beta_l2 = if (length(beta)) sqrt(sum(beta^2)) else NA_real_,
    beta_max_abs = if (length(beta)) max(abs(beta)) else NA_real_,
    beta_cov_trace = if (length(covariance)) sum(diag(covariance)) else NA_real_,
    sigma = r66_safe_sigma(fit),
    gamma = r66_safe_gamma(fit),
    stringsAsFactors = FALSE
  )
}

r66_trace_value <- function(x, i, mode = c("numeric", "logical", "character")) {
  mode <- match.arg(mode)
  if (is.null(x) || length(x) < i) {
    return(switch(mode, numeric = NA_real_, logical = NA, character = NA_character_))
  }
  switch(mode, numeric = as.numeric(x[[i]]), logical = as.logical(x[[i]]), character = as.character(x[[i]]))
}

r66_trace_frame <- function(fit, method_id, likelihood, tau) {
  misc <- fit$misc %||% list()
  n <- max(
    as.integer(fit$iter %||% 0L),
    length(misc$elbo_trace %||% numeric()),
    length(misc$sigma_trace %||% numeric()),
    length(misc$sigmagam_update_performed_trace %||% logical()),
    1L
  )
  do.call(rbind, lapply(seq_len(n), function(i) {
    data.frame(
      method_id = method_id,
      likelihood_family = likelihood,
      tau = as.numeric(tau),
      iter = i,
      elbo = r66_trace_value(misc$elbo_trace %||% misc$elbo, i),
      sigma = r66_trace_value(misc$sigma_trace, i),
      gamma = r66_trace_value(misc$gamma_trace, i),
      parameter_change = r66_trace_value(misc$new_term_trace, i),
      rhs_tau = r66_trace_value(misc$rhs_tau_trace, i),
      rhs_c2 = r66_trace_value(misc$rhs_c2_trace, i),
      rhs_lambda_mean = r66_trace_value(misc$rhs_lambda_mean_trace, i),
      sigmagam_frozen = r66_trace_value(misc$sigmagam_frozen_trace, i, "logical"),
      sigmagam_update_performed = r66_trace_value(misc$sigmagam_update_performed_trace, i, "logical"),
      sigmagam_update_reason = r66_trace_value(misc$sigmagam_update_reason_trace, i, "character"),
      sigmagam_moment_commit = r66_trace_value(misc$structured_moment_commit_trace, i, "character"),
      stringsAsFactors = FALSE
    )
  }))
}

r66_prediction_frame <- function(fit, X, rows, method_id, tau, split = "val") {
  prediction <- as.numeric(X %*% fit$qbeta$m)
  if (length(prediction) != nrow(rows)) {
    stop("Prediction/row mismatch for ", method_id, " at tau ", tau, call. = FALSE)
  }
  data.frame(
    method_id = method_id,
    split = split,
    origin_id = rows$origin_id,
    horizon = rows$horizon,
    tau = as.numeric(tau),
    pred_scaled = prediction,
    stringsAsFactors = FALSE
  )
}

r66_status_is_valid <- function(status_path, fit_path, expected) {
  if (!file.exists(status_path) || !file.exists(fit_path)) return(FALSE)
  status <- tryCatch(jsonlite::read_json(status_path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(status)) return(FALSE)
  keys <- names(expected)
  if (!all(vapply(keys, function(key) identical(as.character(status[[key]]), as.character(expected[[key]])), logical(1)))) {
    return(FALSE)
  }
  identical(as.character(status$fit_sha256), r66_sha256(fit_path))
}

r66_external_fit_contract <- function(contract, expected_status = list()) {
  if (is.null(contract) || !isTRUE(contract$authorized %||% TRUE)) return(NULL)
  fit_path <- normalizePath(as.character(contract$fit_path), mustWork = TRUE)
  status_path <- normalizePath(as.character(contract$status_path), mustWork = TRUE)
  observed_fit_sha256 <- r66_sha256(fit_path)
  if (!identical(observed_fit_sha256, as.character(contract$fit_sha256))) {
    stop("External checkpoint fit hash mismatch: ", fit_path, call. = FALSE)
  }
  status <- jsonlite::read_json(status_path, simplifyVector = TRUE)
  if (!identical(as.character(status$fit_sha256), observed_fit_sha256)) {
    stop("External checkpoint status does not bind its fit: ", status_path, call. = FALSE)
  }
  for (key in names(expected_status)) {
    if (!identical(as.character(status[[key]]), as.character(expected_status[[key]]))) {
      stop("External checkpoint status mismatch for ", key, ": ", status_path, call. = FALSE)
    }
  }
  list(
    fit_path = fit_path,
    status_path = status_path,
    fit_sha256 = observed_fit_sha256,
    status = status
  )
}
