# Opt-in dispatch and compatibility adapters for exact/structured exQDESN inference.

app_joint_exqdesn_method_registry_path <- function() {
  app_path("application/config/joint_exqdesn_inference_method_registry_v1.csv")
}

app_joint_exqdesn_load_method_registry <- function(
  path = app_joint_exqdesn_method_registry_path()
) {
  path <- normalizePath(path, mustWork = TRUE)
  registry <- app_read_csv(path)
  required <- c(
    "registry_version", "method_id", "inference_family", "augmentation",
    "scale_shape_factor", "gamma_coordinate", "sigma_collapsed",
    "exact_target", "candidate_role", "legacy_default", "enabled", "description"
  )
  missing <- setdiff(required, names(registry))
  if (length(missing)) {
    stop(sprintf("The joint exQDESN inference method registry is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if (anyDuplicated(registry$method_id) || any(!nzchar(registry$method_id))) {
    stop("Inference method identifiers must be nonempty and unique.", call. = FALSE)
  }
  if (length(unique(registry$registry_version)) != 1L) {
    stop("The method registry must contain exactly one registry version.", call. = FALSE)
  }
  registry$sigma_collapsed <- as.logical(registry$sigma_collapsed)
  registry$exact_target <- as.logical(registry$exact_target)
  registry$legacy_default <- as.logical(registry$legacy_default)
  registry$enabled <- as.logical(registry$enabled)
  if (any(is.na(registry[, c("sigma_collapsed", "exact_target", "legacy_default", "enabled")]))) {
    stop("Method registry logical fields are malformed.", call. = FALSE)
  }
  registry
}

app_joint_exqdesn_method_row <- function(method_id, inference_family = NULL) {
  registry <- app_joint_exqdesn_load_method_registry()
  row <- registry[registry$method_id == method_id, , drop = FALSE]
  if (nrow(row) != 1L || !isTRUE(row$enabled[[1L]])) {
    stop(sprintf("Unknown or disabled exQDESN inference method '%s'.", method_id), call. = FALSE)
  }
  if (!is.null(inference_family) && !identical(row$inference_family[[1L]], inference_family)) {
    stop(sprintf("Method '%s' is not a %s method.", method_id, inference_family), call. = FALSE)
  }
  row
}

app_joint_exqdesn_filter_call_args <- function(fun, args) {
  formal_names <- names(formals(fun))
  if ("..." %in% formal_names) return(args)
  args[names(args) %in% formal_names]
}

app_joint_exqdesn_attach_method_metadata <- function(fit, method_row, fit_structure) {
  fit$inference_method_id <- method_row$method_id[[1L]]
  fit$inference_registry_version <- method_row$registry_version[[1L]]
  fit$inference_family <- method_row$inference_family[[1L]]
  fit$inference_augmentation <- method_row$augmentation[[1L]]
  fit$scale_shape_factor <- method_row$scale_shape_factor[[1L]]
  fit$gamma_coordinate <- method_row$gamma_coordinate[[1L]]
  fit$sigma_collapsed <- method_row$sigma_collapsed[[1L]]
  fit$exact_target <- method_row$exact_target[[1L]]
  fit$fit_structure <- fit_structure
  if (!is.null(fit$manifest) && is.data.frame(fit$manifest)) {
    fit$manifest$inference_method_id <- method_row$method_id[[1L]]
    fit$manifest$inference_registry_version <- method_row$registry_version[[1L]]
    fit$manifest$fit_structure <- fit_structure
  }
  fit
}

app_joint_exqdesn_validate_fit_contract <- function(
  fit,
  inference_family = c("vb", "mcmc"),
  fit_structure = c("joint", "independent")
) {
  inference_family <- match.arg(inference_family)
  fit_structure <- match.arg(fit_structure)
  required <- if (identical(inference_family, "vb")) {
    c("beta_mean", "alpha_mean", "sigma_mean", "gamma_mean", "qhat_mean", "tau")
  } else {
    c("beta_draws", "alpha_draws", "sigma_draws", "gamma_draws", "qhat_mean", "tau")
  }
  missing <- setdiff(required, names(fit))
  if (length(missing)) {
    stop(sprintf("%s %s fit is missing: %s", fit_structure, inference_family, paste(missing, collapse = ", ")), call. = FALSE)
  }
  numeric_objects <- fit[intersect(required, names(fit))]
  finite <- vapply(numeric_objects, function(x) all(is.finite(as.numeric(x))), logical(1L))
  if (any(!finite)) {
    stop(sprintf("%s %s fit contains nonfinite contract fields: %s", fit_structure, inference_family, paste(names(finite)[!finite], collapse = ", ")), call. = FALSE)
  }
  qhat <- as.matrix(fit$qhat_mean)
  tau <- app_joint_qvp_validate_tau_grid(fit$tau)
  if (ncol(qhat) != length(tau)) stop("Fit qhat columns do not match tau.", call. = FALSE)
  if (any(as.numeric(fit$sigma_mean) <= 0)) stop("Fit scale summaries must be positive.", call. = FALSE)
  invisible(TRUE)
}

app_joint_exqdesn_fit_vb_dispatch <- function(method_id = NULL, ...) {
  args <- list(...)
  if (is.null(method_id)) {
    fit <- do.call(app_joint_qvp_fit_exal_vb_ld_tiny, app_joint_exqdesn_filter_call_args(app_joint_qvp_fit_exal_vb_ld_tiny, args))
    fit$inference_method_id <- "legacy_implicit_VB0_point_v"
    fit$fit_structure <- "joint"
    return(fit)
  }
  method <- app_joint_exqdesn_method_row(method_id, "vb")
  if (identical(method_id, "VB0_point_v")) {
    fit <- do.call(app_joint_qvp_fit_exal_vb_ld_tiny, app_joint_exqdesn_filter_call_args(app_joint_qvp_fit_exal_vb_ld_tiny, args))
  } else if (identical(method_id, "VB1_structured_v")) {
    args$augmentation <- "v"
    args$method_id <- method_id
    fit <- do.call(app_joint_exqdesn_fit_exal_vb_structured, app_joint_exqdesn_filter_call_args(app_joint_exqdesn_fit_exal_vb_structured, args))
  } else if (identical(method_id, "VB2_structured_u")) {
    args$augmentation <- "u"
    args$method_id <- method_id
    fit <- do.call(app_joint_exqdesn_fit_exal_vb_structured, app_joint_exqdesn_filter_call_args(app_joint_exqdesn_fit_exal_vb_structured, args))
  } else {
    stop(sprintf("VB method '%s' has no dispatch implementation.", method_id), call. = FALSE)
  }
  fit <- app_joint_exqdesn_attach_method_metadata(fit, method, "joint")
  app_joint_exqdesn_validate_fit_contract(fit, "vb", "joint")
  fit
}

app_joint_exqdesn_fit_mcmc_dispatch <- function(method_id = NULL, ...) {
  args <- list(...)
  if (is.null(method_id) || identical(method_id, "MCMC_legacy_default")) {
    fit <- do.call(app_joint_qvp_fit_exal_mcmc_tiny, app_joint_exqdesn_filter_call_args(app_joint_qvp_fit_exal_mcmc_tiny, args))
    if (is.null(method_id)) {
      fit$inference_method_id <- "legacy_implicit_bounded_slice"
      fit$fit_structure <- "joint"
      return(fit)
    }
    method <- app_joint_exqdesn_method_row(method_id, "mcmc")
  } else {
    method <- app_joint_exqdesn_method_row(method_id, "mcmc")
    if (identical(method_id, "M0_v_collapsed_support_logit")) {
      args$gamma_update <- "collapsed_logit_slice"
      args$gamma_refresh_repeats <- 1L
      args$gamma_refresh_block <- "none"
      fit <- do.call(app_joint_qvp_fit_exal_mcmc_tiny, app_joint_exqdesn_filter_call_args(app_joint_qvp_fit_exal_mcmc_tiny, args))
    } else if (identical(method_id, "M1b_u_collapsed_support_logit")) {
      args$gamma_coordinate <- "support_logit"
      args$method_id <- method_id
      fit <- do.call(app_joint_exqdesn_fit_exal_mcmc_u_collapsed, app_joint_exqdesn_filter_call_args(app_joint_exqdesn_fit_exal_mcmc_u_collapsed, args))
    } else if (identical(method_id, "M1_u_collapsed_p_logit")) {
      args$gamma_coordinate <- "p_gamma_logit"
      args$method_id <- method_id
      fit <- do.call(app_joint_exqdesn_fit_exal_mcmc_u_collapsed, app_joint_exqdesn_filter_call_args(app_joint_exqdesn_fit_exal_mcmc_u_collapsed, args))
    } else {
      stop(sprintf("MCMC method '%s' has no production-chain dispatch implementation.", method_id), call. = FALSE)
    }
  }
  fit <- app_joint_exqdesn_attach_method_metadata(fit, method, "joint")
  app_joint_exqdesn_validate_fit_contract(fit, "mcmc", "joint")
  fit
}

app_joint_exqdesn_fit_independent_vb_dispatch <- function(method_id, y, Z, tau, init = NULL, ...) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Z <- app_joint_qvp_check_design(Z)
  K <- length(tau)
  p <- ncol(Z)
  extra <- list(...)
  alpha_prior_sd <- extra$alpha_prior_sd %||% Inf
  gamma_init <- extra$gamma_init %||% NULL
  fits <- vector("list", K)
  qhat <- matrix(NA_real_, length(y), K)
  for (k in seq_len(K)) {
    args <- extra
    args$y <- y
    args$Z <- Z
    args$tau <- tau[[k]]
    args$alpha_min_spacing <- 0
    args$alpha_prior_sd <- if (length(alpha_prior_sd) == 1L) alpha_prior_sd else alpha_prior_sd[[k]]
    if (!is.null(gamma_init)) args$gamma_init <- if (length(gamma_init) == 1L) gamma_init else gamma_init[[k]]
    args$init <- if (!is.null(init$fits)) init$fits[[k]] else init
    fits[[k]] <- do.call(app_joint_exqdesn_fit_vb_dispatch, c(list(method_id = method_id), args))
    qhat[, k] <- as.numeric(fits[[k]]$qhat_mean[, 1L])
  }
  out <- list(
    fits = fits,
    qhat_mean = qhat,
    beta_mean = unlist(lapply(fits, `[[`, "beta_mean"), use.names = FALSE),
    alpha_mean = vapply(fits, function(x) x$alpha_mean[[1L]], numeric(1L)),
    sigma_mean = vapply(fits, function(x) x$sigma_mean[[1L]], numeric(1L)),
    gamma_mean = vapply(fits, function(x) x$gamma_mean[[1L]], numeric(1L)),
    tau = tau,
    converged = all(vapply(fits, function(x) isTRUE(x$converged), logical(1L))),
    inference_method_id = method_id,
    fit_structure = "independent",
    component_method_ids = vapply(fits, `[[`, character(1L), "inference_method_id"),
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat, tau)
  )
  colnames(out$qhat_mean) <- paste0("tau_", format(tau, trim = TRUE))
  app_joint_exqdesn_validate_fit_contract(out, "vb", "independent")
  class(out) <- c("independent_exqdesn_vb_fit", "list")
  out
}

app_joint_exqdesn_combine_independent_mcmc <- function(fits, Z, tau, seed = NA_integer_) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  p <- ncol(Z)
  n_keep <- nrow(fits[[1L]]$beta_draws)
  if (any(vapply(fits, function(x) nrow(x$beta_draws), integer(1L)) != n_keep)) {
    stop("Independent MCMC components must retain the same number of draws.", call. = FALSE)
  }
  beta_draws <- matrix(NA_real_, n_keep, K * p)
  alpha_draws <- sigma_draws <- gamma_draws <- matrix(NA_real_, n_keep, K)
  for (k in seq_len(K)) {
    idx <- ((k - 1L) * p + 1L):(k * p)
    beta_draws[, idx] <- fits[[k]]$beta_draws
    alpha_draws[, k] <- fits[[k]]$alpha_draws[, 1L]
    sigma_draws[, k] <- fits[[k]]$sigma_draws[, 1L]
    gamma_draws[, k] <- fits[[k]]$gamma_draws[, 1L]
  }
  beta_mean <- colMeans(beta_draws)
  alpha_mean <- colMeans(alpha_draws)
  qhat <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) + matrix(alpha_mean, nrow(Z), K, byrow = TRUE)
  out <- list(
    fits = fits,
    beta_draws = beta_draws,
    alpha_draws = alpha_draws,
    sigma_draws = sigma_draws,
    gamma_draws = gamma_draws,
    beta_mean = beta_mean,
    alpha_mean = alpha_mean,
    sigma_mean = colMeans(sigma_draws),
    gamma_mean = colMeans(gamma_draws),
    qhat_mean = qhat,
    tau = tau,
    seed = seed,
    fit_structure = "independent",
    inference_method_id = fits[[1L]]$inference_method_id,
    component_method_ids = vapply(fits, `[[`, character(1L), "inference_method_id"),
    init_source = paste(sort(unique(vapply(fits, function(x) x$init_source %||% NA_character_, character(1L)))), collapse = ";"),
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat, tau)
  )
  class(out) <- c("independent_exqdesn_mcmc_fit", "joint_qvp_qdesn_tiny_fit", "list")
  app_joint_exqdesn_validate_fit_contract(out, "mcmc", "independent")
  out
}

app_joint_exqdesn_fit_independent_mcmc_dispatch <- function(
  method_id,
  y,
  Z,
  tau,
  seed,
  init = NULL,
  tau_seed_stride = 1009L,
  ...
) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Z <- app_joint_qvp_check_design(Z)
  extra <- list(...)
  alpha_prior_sd <- extra$alpha_prior_sd %||% Inf
  gamma_init <- extra$gamma_init %||% NULL
  fits <- vector("list", length(tau))
  for (k in seq_along(tau)) {
    args <- extra
    args$y <- y
    args$Z <- Z
    args$tau <- tau[[k]]
    args$seed <- as.integer(seed + k * as.integer(tau_seed_stride))
    args$alpha_min_spacing <- 0
    args$alpha_prior_sd <- if (length(alpha_prior_sd) == 1L) alpha_prior_sd else alpha_prior_sd[[k]]
    if (!is.null(gamma_init)) args$gamma_init <- if (length(gamma_init) == 1L) gamma_init else gamma_init[[k]]
    args$init <- if (!is.null(init$fits)) init$fits[[k]] else init
    fits[[k]] <- do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(list(method_id = method_id), args))
  }
  app_joint_exqdesn_combine_independent_mcmc(fits, Z, tau, seed)
}
