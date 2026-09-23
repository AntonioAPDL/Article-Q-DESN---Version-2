# State and provenance helpers for corrected GloFAS quantile certification restarts.

app_glofas_restart_hash_object <- function(x) {
  path <- tempfile("glofas_restart_object_", fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(x, path, version = 2L)
  app_sha256_file(path)
}

app_glofas_restart_tau_equal <- function(observed, expected, tolerance = 1.0e-12) {
  observed <- as.numeric(observed)
  expected <- as.numeric(expected)
  length(observed) == length(expected) &&
    all(is.finite(observed)) && all(is.finite(expected)) &&
    max(abs(observed - expected)) <= tolerance
}

app_glofas_restart_validate_matrix <- function(x, nr, nc, label, positive = FALSE) {
  x <- as.matrix(x)
  if (!identical(dim(x), c(as.integer(nr), as.integer(nc))) ||
      any(!is.finite(x)) || (isTRUE(positive) && any(x <= 0))) {
    stop(sprintf("Restart field %s has incompatible dimensions or values.", label), call. = FALSE)
  }
  x
}

app_glofas_restart_validate_covariance_blocks <- function(blocks, K, p, label) {
  if (!is.list(blocks) || length(blocks) != K) {
    stop(sprintf("Restart %s must contain exactly %d covariance blocks.", label, K), call. = FALSE)
  }
  lapply(seq_len(K), function(kk) {
    value <- app_glofas_restart_validate_matrix(
      blocks[[kk]], p, p, sprintf("%s[[%d]]", label, kk)
    )
    if (max(abs(value - t(value))) > 1.0e-7 || any(diag(value) < 0)) {
      stop(sprintf("Restart %s block %d is not a valid symmetric covariance.", label, kk), call. = FALSE)
    }
    value
  })
}

app_glofas_restart_source_iterations <- function(fit) {
  value <- fit$iterations_completed %||%
    fit$iteration_contract$completed_iterations %||%
    fit$iterations %||%
    nrow(fit$trace %||% data.frame())
  value <- as.integer(value)
  if (length(value) != 1L || is.na(value) || value < 1L) {
    stop("Restart source lacks a valid completed-iteration count.", call. = FALSE)
  }
  value
}

app_glofas_restart_prior_fields_part12 <- function(controls) {
  controls <- as.list(controls)
  controls[c(
    "tau0", "zeta2", "slab_fixed", "a_sigma", "b_sigma",
    "alpha_prior_sd", "rhs_vb_inner", "exal_method_id"
  )]
}

app_glofas_restart_prior_fields_part3 <- function(controls) {
  controls <- as.list(controls)
  controls[c(
    "tau0_reference", "tau0_discrepancy", "slab_s2", "a_zeta", "b_zeta",
    "zeta2_fixed_reference", "zeta2_fixed_discrepancy", "a_sigma", "b_sigma",
    "rhs_vb_inner", "quadrature_nodes", "quadrature_tolerance"
  )]
}

app_glofas_restart_prior_signature <- function(controls, part = c("part12", "part3")) {
  part <- match.arg(part)
  fields <- if (identical(part, "part12")) {
    app_glofas_restart_prior_fields_part12(controls)
  } else {
    app_glofas_restart_prior_fields_part3(controls)
  }
  list(fields = fields, sha256 = app_glofas_restart_hash_object(fields))
}

app_glofas_restart_assert_prior_identity <- function(source_controls, restart_controls, part) {
  source <- app_glofas_restart_prior_signature(source_controls, part)
  restart <- app_glofas_restart_prior_signature(restart_controls, part)
  if (!identical(source$sha256, restart$sha256)) {
    stop("Certification restart changes fixed prior hyperparameters.", call. = FALSE)
  }
  list(source = source, restart = restart)
}

app_glofas_part12_build_restart_state <- function(
  fit,
  model_family,
  tau,
  p,
  n,
  source_path = NA_character_,
  source_sha256 = NA_character_
) {
  fit <- app_glofas_quantile_unwrap_fit(fit)
  tau <- as.numeric(tau)
  K <- length(tau)
  if (!is.list(fit) || !app_glofas_restart_tau_equal(fit$tau, tau)) {
    stop("Part 1/2 restart source tau grid does not match the destination.", call. = FALSE)
  }
  if (!identical(as.character(fit$model_family), as.character(model_family))) {
    stop("Part 1/2 restart source model family does not match the destination.", call. = FALSE)
  }
  beta <- as.numeric(fit$beta_mean)
  alpha <- as.numeric(fit$alpha_mean)
  sigma <- as.numeric(fit$sigma_mean)
  if (length(beta) != K * p || length(alpha) != K || length(sigma) != K ||
      any(!is.finite(c(beta, alpha, sigma))) || any(sigma <= 0)) {
    stop("Part 1/2 restart source global state is incompatible.", call. = FALSE)
  }
  covariance <- app_glofas_restart_validate_covariance_blocks(
    fit$beta_cov_blocks, K, p, "beta_cov_blocks"
  )
  fallback_rhs <- app_joint_qvp_initialize_rhs_state(
    K, p,
    tau0 = as.numeric(fit$part1_quantile_controls$tau0 %||% fit$part1_quantile_tau0),
    zeta2 = as.numeric(fit$part1_quantile_controls$zeta2 %||% Inf),
    slab_fixed = isTRUE(fit$part1_quantile_controls$slab_fixed)
  )
  rhs_state <- app_joint_qvp_restore_rhs_vb_state(fit$rhs_state, K, p, fallback_rhs)
  local_names <- c("v_mean", "v_inv_mean", "s_mean", "s2_mean")
  local <- lapply(local_names, function(field) {
    value <- fit[[field]]
    if (is.null(value)) return(NULL)
    app_glofas_restart_validate_matrix(value, n, K, field, positive = TRUE)
  })
  names(local) <- local_names
  required_local_names <- if (grepl("exal", tolower(model_family), fixed = TRUE)) {
    local_names
  } else {
    c("v_mean", "v_inv_mean")
  }
  gamma <- fit$gamma_mean %||% NULL
  if (!is.null(gamma)) {
    gamma <- as.numeric(gamma)
    if (length(gamma) != K || any(!is.finite(gamma))) {
      stop("Part 1/2 restart gamma state is incompatible.", call. = FALSE)
    }
  }
  list(
    schema_version = "glofas_quantile_certification_restart_v1",
    restart_kind = if (all(vapply(local[required_local_names], Negate(is.null), logical(1L)))) {
      "exact_local_state_available"
    } else {
      "same_target_reconstructed_local_state"
    },
    model_family = model_family,
    tau = tau,
    p = as.integer(p),
    n = as.integer(n),
    init = list(beta_mean = beta, alpha_mean = alpha, sigma_mean = sigma, gamma_mean = gamma),
    beta_cov_blocks = covariance,
    sigma_shape = fit$sigma_shape %||% NULL,
    sigma_rate = fit$sigma_rate %||% NULL,
    sigma_inv_mean = fit$sigma_inv_mean %||% NULL,
    rhs_state = rhs_state,
    v_mean = local$v_mean,
    v_inv_mean = local$v_inv_mean,
    s_mean = local$s_mean,
    s2_mean = local$s2_mean,
    iterations_completed = app_glofas_restart_source_iterations(fit),
    source_path = as.character(source_path),
    source_sha256 = as.character(source_sha256),
    source_state_sha256 = app_glofas_restart_hash_object(list(
      beta = beta, alpha = alpha, sigma = sigma, gamma = gamma,
      covariance = covariance, rhs_state = rhs_state, local = local
    ))
  )
}

app_glofas_part3_build_restart_state <- function(
  fit,
  tau,
  p_reference,
  p_discrepancy,
  n_stacked,
  source_path = NA_character_,
  source_sha256 = NA_character_
) {
  fit <- app_glofas_quantile_unwrap_fit(fit)
  tau <- as.numeric(tau)
  K <- length(tau)
  if (!is.list(fit) || !app_glofas_restart_tau_equal(fit$tau, tau) ||
      !identical(as.character(fit$fit_structure), "joint") ||
      !identical(toupper(as.character(fit$likelihood)), "AL")) {
    stop("Part 3 restart source identity does not match joint AL.", call. = FALSE)
  }
  beta_reference <- app_glofas_restart_validate_matrix(
    fit$beta_reference_mean, p_reference, K, "beta_reference_mean"
  )
  beta_discrepancy <- app_glofas_restart_validate_matrix(
    fit$beta_discrepancy_mean, p_discrepancy, K, "beta_discrepancy_mean"
  )
  variance_reference <- app_glofas_restart_validate_matrix(
    fit$beta_reference_var_diag, p_reference, K, "beta_reference_var_diag"
  )
  variance_discrepancy <- app_glofas_restart_validate_matrix(
    fit$beta_discrepancy_var_diag, p_discrepancy, K, "beta_discrepancy_var_diag"
  )
  covariance_reference <- app_glofas_restart_validate_covariance_blocks(
    fit$beta_reference_cov_blocks, K, p_reference, "beta_reference_cov_blocks"
  )
  covariance_discrepancy <- app_glofas_restart_validate_covariance_blocks(
    fit$beta_discrepancy_cov_blocks, K, p_discrepancy, "beta_discrepancy_cov_blocks"
  )
  sigma <- as.numeric(fit$sigma_mean)
  if (length(sigma) != K || any(!is.finite(sigma)) || any(sigma <= 0)) {
    stop("Part 3 restart sigma state is incompatible.", call. = FALSE)
  }
  local <- lapply(c("latent_mean", "latent_inv_mean"), function(field) {
    value <- fit[[field]]
    if (is.null(value)) return(NULL)
    app_glofas_restart_validate_matrix(value, n_stacked, K, field, positive = TRUE)
  })
  names(local) <- c("latent_mean", "latent_inv_mean")
  list(
    schema_version = "glofas_quantile_certification_restart_v1",
    restart_kind = if (all(vapply(local, Negate(is.null), logical(1L)))) {
      "exact_local_state_available"
    } else {
      "same_target_reconstructed_local_state"
    },
    model_family = fit$model_family,
    likelihood = fit$likelihood,
    fit_structure = fit$fit_structure,
    tau = tau,
    initialized = list(
      beta_reference = beta_reference,
      beta_discrepancy = beta_discrepancy,
      var_reference = variance_reference,
      var_discrepancy = variance_discrepancy,
      covariance_reference = covariance_reference,
      covariance_discrepancy = covariance_discrepancy,
      sigma = sigma,
      sigma_shape = fit$sigma_shape %||% NULL,
      sigma_rate = fit$sigma_rate %||% NULL,
      gamma = fit$gamma_mean %||% NULL,
      rhs_state_reference = fit$rhs_state_reference,
      rhs_state_discrepancy = fit$rhs_state_discrepancy,
      latent_mean = local$latent_mean,
      latent_inv_mean = local$latent_inv_mean,
      provenance = data.frame(
        source_path = as.character(source_path), source_sha256 = as.character(source_sha256),
        source_class = paste(class(fit), collapse = ";"), source_tau = tau,
        target_tau = tau, source_column = seq_along(tau),
        mapping_status = "exact_tau_restart", stringsAsFactors = FALSE
      )
    ),
    iterations_completed = app_glofas_restart_source_iterations(fit),
    source_path = as.character(source_path),
    source_sha256 = as.character(source_sha256),
    source_state_sha256 = app_glofas_restart_hash_object(list(
      beta_reference = beta_reference, beta_discrepancy = beta_discrepancy,
      variance_reference = variance_reference, variance_discrepancy = variance_discrepancy,
      covariance_reference = covariance_reference, covariance_discrepancy = covariance_discrepancy,
      sigma = sigma, rhs_reference = fit$rhs_state_reference,
      rhs_discrepancy = fit$rhs_state_discrepancy, local = local
    ))
  )
}

app_glofas_restart_checkpoint_metadata <- function(restart_state, completed_iterations) {
  list(
    schema_version = "glofas_quantile_checkpoint_v1",
    complete_local_state = TRUE,
    restart_kind = restart_state$restart_kind %||% "fresh_fit",
    source_path = restart_state$source_path %||% NA_character_,
    source_sha256 = restart_state$source_sha256 %||% NA_character_,
    source_state_sha256 = restart_state$source_state_sha256 %||% NA_character_,
    iterations_completed = as.integer(completed_iterations)
  )
}

app_glofas_restart_combine_traces <- function(source_trace, restart_trace) {
  source_trace <- as.data.frame(source_trace %||% data.frame())
  restart_trace <- as.data.frame(restart_trace %||% data.frame())
  if (!nrow(source_trace) || !nrow(restart_trace)) {
    stop("Both source and restart traces are required for a cumulative trace.", call. = FALSE)
  }
  source_iterations <- max(as.integer(
    source_trace$global_iter %||% source_trace$iter %||% seq_len(nrow(source_trace))
  ))
  source_trace$segment <- "source"
  source_trace$segment_iter <- as.integer(source_trace$iter %||% seq_len(nrow(source_trace)))
  source_trace$global_iter <- as.integer(
    source_trace$global_iter %||% source_trace$iter %||% seq_len(nrow(source_trace))
  )
  restart_trace$segment <- "certification_restart"
  restart_trace$segment_iter <- as.integer(restart_trace$iter %||% seq_len(nrow(restart_trace)))
  observed_global <- as.integer(restart_trace$global_iter %||% (source_iterations + seq_len(nrow(restart_trace))))
  expected_global <- source_iterations + seq_len(nrow(restart_trace))
  if (!identical(observed_global, as.integer(expected_global))) {
    stop("Restart trace does not continue the cumulative iteration index exactly.", call. = FALSE)
  }
  restart_trace$global_iter <- observed_global
  app_bind_rows_fill(list(source_trace, restart_trace))
}

app_glofas_restart_certificate_row <- function(
  fit,
  source_fit_sha256,
  source_state_sha256,
  prior_identity,
  expected_segment_iterations = 200L,
  expected_source_iterations = 200L
) {
  trace <- as.data.frame(fit$trace %||% data.frame())
  certificate <- fit$convergence_certificate %||% fit$terminal_certificate %||% list()
  global_iter <- as.integer(trace$global_iter %||% integer())
  segment_ok <- nrow(trace) == as.integer(expected_segment_iterations)
  global_ok <- segment_ok && identical(
    global_iter,
    as.integer(expected_source_iterations + seq_len(expected_segment_iterations))
  )
  checkpoint <- fit$checkpoint_state %||% list()
  complete_state <- isTRUE(checkpoint$complete_local_state) &&
    isTRUE(length(fit$beta_cov_blocks %||% fit$beta_reference_cov_blocks) > 0L) &&
    !is.null(fit$rhs_state %||% fit$rhs_state_reference)
  data.frame(
    source_fit_sha256 = as.character(source_fit_sha256),
    source_state_sha256 = as.character(source_state_sha256),
    source_iterations = as.integer(expected_source_iterations),
    restart_iterations = nrow(trace),
    cumulative_iterations = as.integer(fit$iterations_completed %||% NA_integer_),
    segment_length_ok = segment_ok,
    global_iteration_sequence_ok = global_ok,
    prior_identity_ok = identical(prior_identity$source$sha256, prior_identity$restart$sha256),
    complete_checkpoint_state = complete_state,
    terminal_certificate_passed = isTRUE(certificate$passed),
    certified = isTRUE(
      segment_ok && global_ok &&
      identical(prior_identity$source$sha256, prior_identity$restart$sha256) &&
      complete_state && isTRUE(certificate$passed)
    ),
    stringsAsFactors = FALSE
  )
}
