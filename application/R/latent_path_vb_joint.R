# Joint-quantile RHS coordination for GloFAS Part 4 latent-path fits.

app_latent_joint_extract_core_fit <- function(x) {
  fit <- x$fit %||% x
  if (!is.list(fit) || is.null(fit$summary$theta_mean) || is.null(fit$summary$y_future_mean)) {
    stop("Each Part 4 joint initializer must contain a completed latent-path fit.", call. = FALSE)
  }
  fit
}

app_latent_joint_initial_state <- function(fit) {
  list(
    theta_mean = as.numeric(fit$summary$theta_mean),
    theta_cov = as.matrix(fit$summary$theta_cov),
    y_future_mean = as.numeric(fit$summary$y_future_mean),
    y_future_cov = as.matrix(fit$summary$y_future_cov),
    sigma_state = fit$variational_state$sigma %||% NULL,
    sigma_mean = fit$summary$sigma_mean %||% NULL,
    gamma = fit$summary$gamma_mean %||% NULL,
    provenance = list(type = "same_tau_independent_fit")
  )
}

app_latent_joint_prior_additions <- function(reference_terms, discrepancy_terms, design, k) {
  diagonal <- linear <- numeric(ncol(design$H_fixed))
  diagonal[design$beta_index] <- reference_terms$diagonal[[k]]
  linear[design$beta_index] <- reference_terms$linear[[k]]
  diagonal[design$alpha_index] <- discrepancy_terms$diagonal[[k]]
  linear[design$alpha_index] <- discrepancy_terms$linear[[k]]
  list(diagonal = diagonal, linear = linear)
}

app_fit_latent_path_joint_vb_core <- function(
  designs,
  tau,
  likelihood = c("al", "exal"),
  independent_fits,
  vb_args = list(),
  seed = NULL
) {
  likelihood <- match.arg(likelihood)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  if (K < 2L) stop("Joint Part 4 fitting requires at least two quantiles.", call. = FALSE)
  if (!is.list(designs) || !length(designs)) stop("Joint Part 4 fitting requires latent-path designs.", call. = FALSE)
  if (length(designs) == 1L) designs <- rep(designs, K)
  if (length(designs) != K || length(independent_fits) != K) {
    stop("Joint Part 4 designs and independent initializers must match the quantile grid.", call. = FALSE)
  }
  fits <- lapply(independent_fits, app_latent_joint_extract_core_fit)
  p_reference <- length(designs[[1L]]$beta_index)
  p_discrepancy <- length(designs[[1L]]$alpha_index)
  if (any(vapply(designs, function(x) length(x$beta_index) != p_reference ||
      length(x$alpha_index) != p_discrepancy, logical(1L)))) {
    stop("All joint Part 4 designs must use identical coefficient dimensions.", call. = FALSE)
  }
  theta_names <- lapply(designs, function(x) colnames(x$H_fixed))
  if (any(!vapply(theta_names[-1L], identical, logical(1L), theta_names[[1L]]))) {
    stop("All joint Part 4 designs must use identical coefficient coordinates.", call. = FALSE)
  }
  controls <- app_glofas_part3_rhs_default_controls(
    tau0_reference = as.numeric(vb_args$beta_rhs$tau0 %||% 1),
    tau0_discrepancy = as.numeric(vb_args$alpha_rhs$tau0 %||% 1.0e-3),
    slab_s2 = as.numeric(vb_args$beta_rhs$slab_s2 %||% 1),
    a_zeta = as.numeric(vb_args$beta_rhs$a_zeta %||% 2),
    b_zeta = as.numeric(vb_args$beta_rhs$b_zeta %||% 4),
    update_every = as.integer((vb_args$rhs %||% list())$update_every %||% 1L),
    freeze_tau_warmup_iters = as.integer((vb_args$rhs %||% list())$freeze_tau_warmup_iters %||% 0L),
    min_tau_updates = as.integer((vb_args$rhs %||% list())$min_tau_updates %||% 0L)
  )
  coefficient_moments <- function(fit_list) {
    reference_mean <- do.call(cbind, lapply(fit_list, function(x) x$summary$theta_mean[designs[[1L]]$beta_index]))
    discrepancy_mean <- do.call(cbind, lapply(fit_list, function(x) x$summary$theta_mean[designs[[1L]]$alpha_index]))
    reference_var <- do.call(cbind, lapply(fit_list, function(x) diag(x$summary$theta_cov)[designs[[1L]]$beta_index]))
    discrepancy_var <- do.call(cbind, lapply(fit_list, function(x) diag(x$summary$theta_cov)[designs[[1L]]$alpha_index]))
    list(reference_mean = reference_mean, discrepancy_mean = discrepancy_mean,
         reference_var = reference_var, discrepancy_var = discrepancy_var)
  }
  moments <- coefficient_moments(fits)
  rhs_reference <- app_glofas_part3_rhs_initialize(
    K, p_reference, controls$tau0_reference, controls,
    coefficient_mean = moments$reference_mean,
    coefficient_var_diag = moments$reference_var
  )
  rhs_discrepancy <- app_glofas_part3_rhs_initialize(
    K, p_discrepancy, controls$tau0_discrepancy, controls,
    coefficient_mean = moments$discrepancy_mean,
    coefficient_var_diag = moments$discrepancy_var
  )
  outer_max <- as.integer(vb_args$joint_outer_max_iter %||% 5L)
  outer_min <- as.integer(vb_args$joint_outer_min_iter %||% 2L)
  outer_tol <- as.numeric(vb_args$joint_outer_tol %||% 1.0e-3)
  inner_max <- as.integer(vb_args$joint_inner_max_iter %||% 30L)
  inner_min <- as.integer(vb_args$joint_inner_min_iter %||% min(10L, inner_max))
  if (outer_max < 1L || outer_min < 1L || outer_min > outer_max || inner_max < 2L ||
      inner_min < 1L || inner_min > inner_max || outer_tol <= 0) {
    stop("Invalid joint Part 4 CAVI controls.", call. = FALSE)
  }
  seed <- as.integer(seed %||% vb_args$seed %||% 20260513L)
  trace <- vector("list", outer_max)
  started <- Sys.time()
  converged <- FALSE

  for (outer in seq_len(outer_max)) {
    old_theta <- do.call(cbind, lapply(fits, function(x) x$summary$theta_mean))
    ref_terms <- app_glofas_part3_rhs_prior_terms(rhs_reference, moments$reference_mean)
    disc_terms <- app_glofas_part3_rhs_prior_terms(rhs_discrepancy, moments$discrepancy_mean)
    for (k in seq_len(K)) {
      design <- designs[[k]]
      design$p0 <- tau[[k]]
      inner_args <- vb_args
      inner_args$max_iter <- inner_max
      inner_args$min_iter_elbo <- inner_min
      inner_args$n_draws <- as.integer(vb_args$n_draws %||% 500L)
      inner_args$freeze_beta_warmup_iters <- 0L
      inner_args$min_beta_updates <- 1L
      inner_args$beta_ridge <- list(precision = 1.0e-12)
      inner_args$initial_state <- app_latent_joint_initial_state(fits[[k]])
      inner_args$prior_addition <- app_latent_joint_prior_additions(ref_terms, disc_terms, design, k)
      fits[[k]] <- if (identical(likelihood, "al")) {
        inner_args$likelihood_family <- "al"
        app_fit_latent_path_al_vb_core(
          design, tau[[k]], coefficient_prior = "ridge", vb_args = inner_args,
          seed = seed + outer * 1000L + k
        )
      } else {
        app_fit_latent_path_exal_vb_core(
          design, tau[[k]], coefficient_prior = "ridge", vb_args = inner_args,
          seed = seed + outer * 1000L + k
        )
      }
    }
    moments <- coefficient_moments(fits)
    rhs_reference <- app_glofas_part3_rhs_update(
      rhs_reference, moments$reference_mean, moments$reference_var, iter = outer
    )
    rhs_discrepancy <- app_glofas_part3_rhs_update(
      rhs_discrepancy, moments$discrepancy_mean, moments$discrepancy_var, iter = outer
    )
    new_theta <- do.call(cbind, lapply(fits, function(x) x$summary$theta_mean))
    change <- max(abs(new_theta - old_theta) / pmax(1, abs(old_theta)))
    trace[[outer]] <- data.frame(
      outer_iteration = outer,
      parameter_change = change,
      all_inner_converged = all(vapply(fits, function(x) isTRUE(x$vb_diagnostics$converged), logical(1L))),
      elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
    message(sprintf("[Part4 joint %s] outer iteration %d/%d change=%.6g", likelihood, outer, outer_max, change))
    if (outer >= outer_min && is.finite(change) && change < outer_tol) {
      converged <- TRUE
      trace <- trace[seq_len(outer)]
      break
    }
  }
  trace <- do.call(rbind, trace[vapply(trace, is.data.frame, logical(1L))])
  list(
    schema_version = "glofas_part4_joint_latent_v1",
    method = "vb",
    likelihood_family = likelihood,
    fit_structure = "joint_adjacent_rhs",
    tau = tau,
    fits = fits,
    beta_reference_mean = moments$reference_mean,
    beta_discrepancy_mean = moments$discrepancy_mean,
    beta_reference_var_diag = moments$reference_var,
    beta_discrepancy_var_diag = moments$discrepancy_var,
    rhs_state_reference = rhs_reference,
    rhs_state_discrepancy = rhs_discrepancy,
    rhs_summary_reference = app_glofas_part3_rhs_summary(rhs_reference, "reference"),
    rhs_summary_discrepancy = app_glofas_part3_rhs_summary(rhs_discrepancy, "discrepancy"),
    rhs_partition_certificate = app_glofas_part3_rhs_partition_certificate(
      p_reference, p_discrepancy, rhs_reference, rhs_discrepancy
    ),
    converged = converged,
    trace = trace,
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    future_truth_policy = designs[[1L]]$future_truth_policy,
    ensemble_weight_contract = "each_horizon_sums_to_one",
    approximation = "mean_field_quantile_blocks_with_adjacent_rhs_coordinate_updates"
  )
}
