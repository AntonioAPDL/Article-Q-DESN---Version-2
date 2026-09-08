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

app_latent_joint_rhs_control <- function(vb_args) {
  inherited <- app_latent_normalize_rhs_control(vb_args$rhs %||% list())
  inner_min <- as.integer(vb_args$joint_inner_min_iter %||% 10L)
  if (!is.finite(inner_min) || inner_min < 1L) {
    stop("Joint RHS warmup conversion requires a positive inner minimum.", call. = FALSE)
  }
  freeze_outer <- vb_args$joint_rhs_freeze_outer_iters %||%
    ceiling(inherited$freeze_tau_warmup_iters / inner_min)
  effective <- app_latent_normalize_rhs_control(list(
    freeze_tau_warmup_iters = freeze_outer,
    update_every = vb_args$joint_rhs_update_every %||% inherited$update_every,
    min_tau_updates = vb_args$joint_rhs_min_tau_updates %||% inherited$min_tau_updates
  ))
  list(
    effective = effective,
    inherited = inherited,
    conversion = "ceil(inherited_vb_warmup_iterations/joint_inner_min_iterations)",
    inner_min_iterations = inner_min
  )
}

app_latent_joint_rhs_gate <- function(states, iter, component) {
  state_names <- names(states)
  rows <- lapply(seq_along(states), function(k) {
    state <- states[[k]]
    control <- app_latent_normalize_rhs_control(state$rhs_control %||% list())
    required <- control$min_tau_updates
    update_count <- as.integer(state$tau_update_count %||% 0L)
    first_update <- as.integer(state$first_tau_update_iter %||% NA_integer_)
    enough_updates <- update_count >= required
    needs_response <- required > 0L || control$freeze_tau_warmup_iters > 0L
    coefficient_response <- !needs_response || (is.finite(first_update) && iter > first_update)
    data.frame(
      component = component,
      rhs_block = if (!is.null(state_names) && nzchar(state_names[[k]])) state_names[[k]] else as.character(k),
      freeze_outer_iters = control$freeze_tau_warmup_iters,
      min_tau_updates = required,
      tau_update_count = update_count,
      first_tau_update_outer = first_update,
      coefficient_response_after_release = coefficient_response,
      passed = enough_updates && coefficient_response,
      stringsAsFactors = FALSE
    )
  })
  rows <- do.call(rbind, rows)
  list(passed = all(rows$passed), blocks = rows)
}

app_latent_joint_validate_continuation <- function(
  initial_joint_fit,
  designs,
  tau,
  likelihood,
  controls,
  allow_rhs_schedule_rebase = FALSE
) {
  if (!is.list(initial_joint_fit) ||
      !identical(initial_joint_fit$schema_version, "glofas_part4_joint_latent_v1") ||
      !identical(initial_joint_fit$fit_structure, "joint_adjacent_rhs")) {
    stop("The joint continuation initializer has an unsupported schema.", call. = FALSE)
  }
  if (!identical(tolower(as.character(initial_joint_fit$likelihood_family)), likelihood)) {
    stop("The joint continuation likelihood does not match the requested likelihood.", call. = FALSE)
  }
  source_tau <- as.numeric(initial_joint_fit$tau)
  if (length(source_tau) != length(tau) || any(abs(source_tau - tau) > 1.0e-12)) {
    stop("The joint continuation quantile grid does not match the requested grid.", call. = FALSE)
  }
  if (length(initial_joint_fit$fits) != length(tau)) {
    stop("The joint continuation fit count does not match the quantile grid.", call. = FALSE)
  }
  fits <- lapply(initial_joint_fit$fits, app_latent_joint_extract_core_fit)
  expected_p <- vapply(designs, function(x) ncol(x$H_fixed), integer(1L))
  observed_p <- vapply(fits, function(x) length(x$summary$theta_mean), integer(1L))
  if (!identical(observed_p, expected_p)) {
    stop("The joint continuation coefficient dimensions do not match the designs.", call. = FALSE)
  }
  expected_names <- lapply(designs, function(x) colnames(x$H_fixed))
  observed_names <- lapply(fits, function(x) names(x$summary$theta_mean))
  named <- vapply(observed_names, function(x) !is.null(x) && length(x), logical(1L))
  if (any(named) && any(!vapply(seq_along(fits), function(k) {
    identical(observed_names[[k]], expected_names[[k]])
  }, logical(1L)))) {
    stop("The joint continuation coefficient coordinates do not match the designs.", call. = FALSE)
  }
  required_rhs <- c("rhs_state_reference", "rhs_state_discrepancy")
  if (any(!vapply(required_rhs, function(x) is.list(initial_joint_fit[[x]]), logical(1L)))) {
    stop("The joint continuation initializer is missing retained RHS states.", call. = FALSE)
  }
  if (length(initial_joint_fit$rhs_state_reference) != length(tau) ||
      length(initial_joint_fit$rhs_state_discrepancy) != length(tau)) {
    stop("The joint continuation RHS state count does not match the quantile grid.", call. = FALSE)
  }
  p_reference <- length(designs[[1L]]$beta_index)
  p_discrepancy <- length(designs[[1L]]$alpha_index)
  invisible(lapply(initial_joint_fit$rhs_state_reference, function(state) {
    app_glofas_part3_rhs_validate_block_state(state, p_reference, controls$tau0_reference)
  }))
  invisible(lapply(initial_joint_fit$rhs_state_discrepancy, function(state) {
    app_glofas_part3_rhs_validate_block_state(state, p_discrepancy, controls$tau0_discrepancy)
  }))
  expected_policy <- unique(vapply(designs, function(x) as.character(x$future_truth_policy), character(1L)))
  if (length(expected_policy) != 1L ||
      !identical(as.character(initial_joint_fit$future_truth_policy), expected_policy)) {
    stop("The joint continuation future-truth policy does not match the designs.", call. = FALSE)
  }
  trace <- initial_joint_fit$trace
  if (!is.data.frame(trace) || !nrow(trace) ||
      any(!c("outer_iteration", "parameter_change", "all_inner_converged") %in% names(trace)) ||
      any(diff(as.integer(trace$outer_iteration)) != 1L)) {
    stop("The joint continuation initializer has an invalid outer trace.", call. = FALSE)
  }
  outer_offset <- max(as.integer(trace$outer_iteration))
  rebase_component <- function(states, component) {
    effective <- app_latent_normalize_rhs_control(controls$rhs_control)
    state_names <- names(states)
    audited <- lapply(seq_along(states), function(k) {
      state <- states[[k]]
      observed <- app_latent_normalize_rhs_control(state$rhs_control %||% list())
      same <- identical(observed, effective)
      if (!same) {
        if (!isTRUE(allow_rhs_schedule_rebase)) {
          stop("The joint continuation RHS schedule differs from the requested schedule.", call. = FALSE)
        }
        if (as.integer(state$tau_update_count %||% 0L) != 0L ||
            outer_offset < effective$freeze_tau_warmup_iters) {
          stop("RHS schedule rebasing is allowed only after a completed warmup with zero global-scale updates.", call. = FALSE)
        }
        state$rhs_control <- effective
      }
      list(
        state = state,
        audit = data.frame(
          component = component,
          rhs_block = if (!is.null(state_names) && nzchar(state_names[[k]])) state_names[[k]] else as.character(k),
          schedule_rebased = !same,
          source_freeze_iters = observed$freeze_tau_warmup_iters,
          effective_freeze_outer_iters = effective$freeze_tau_warmup_iters,
          source_tau_update_count = as.integer(state$tau_update_count %||% 0L),
          stringsAsFactors = FALSE
        )
      )
    })
    states <- lapply(audited, `[[`, "state")
    names(states) <- state_names
    list(states = states, audit = do.call(rbind, lapply(audited, `[[`, "audit")))
  }
  reference_rebase <- rebase_component(initial_joint_fit$rhs_state_reference, "reference")
  discrepancy_rebase <- rebase_component(initial_joint_fit$rhs_state_discrepancy, "discrepancy")
  list(
    fits = fits,
    rhs_reference = reference_rebase$states,
    rhs_discrepancy = discrepancy_rebase$states,
    rhs_schedule_rebase_audit = rbind(reference_rebase$audit, discrepancy_rebase$audit),
    trace = trace,
    previous_runtime_seconds = as.numeric(initial_joint_fit$runtime_seconds %||% 0),
    outer_offset = outer_offset,
    continuation_count = as.integer(initial_joint_fit$continuation_count %||% 0L) + 1L
  )
}

app_fit_latent_path_joint_vb_core <- function(
  designs,
  tau,
  likelihood = c("al", "exal"),
  independent_fits = NULL,
  vb_args = list(),
  seed = NULL,
  initial_joint_fit = NULL
) {
  likelihood <- match.arg(likelihood)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  if (K < 2L) stop("Joint Part 4 fitting requires at least two quantiles.", call. = FALSE)
  if (!is.list(designs) || !length(designs)) stop("Joint Part 4 fitting requires latent-path designs.", call. = FALSE)
  if (length(designs) == 1L) designs <- rep(designs, K)
  if (length(designs) != K) {
    stop("Joint Part 4 designs must match the quantile grid.", call. = FALSE)
  }
  if (is.null(initial_joint_fit) && length(independent_fits) != K) {
    stop("Fresh joint Part 4 fits require one independent initializer per quantile.", call. = FALSE)
  }
  if (!is.null(initial_joint_fit) && !is.null(independent_fits)) {
    stop("Supply either independent initializers or a retained joint fit, not both.", call. = FALSE)
  }
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
  rhs_schedule <- app_latent_joint_rhs_control(vb_args)
  controls <- app_glofas_part3_rhs_default_controls(
    tau0_reference = as.numeric(vb_args$beta_rhs$tau0 %||% 1),
    tau0_discrepancy = as.numeric(vb_args$alpha_rhs$tau0 %||% 1.0e-3),
    slab_s2 = as.numeric(vb_args$beta_rhs$slab_s2 %||% 1),
    a_zeta = as.numeric(vb_args$beta_rhs$a_zeta %||% 2),
    b_zeta = as.numeric(vb_args$beta_rhs$b_zeta %||% 4),
    update_every = rhs_schedule$effective$update_every,
    freeze_tau_warmup_iters = rhs_schedule$effective$freeze_tau_warmup_iters,
    min_tau_updates = rhs_schedule$effective$min_tau_updates
  )
  coefficient_moments <- function(fit_list) {
    reference_mean <- do.call(cbind, lapply(fit_list, function(x) x$summary$theta_mean[designs[[1L]]$beta_index]))
    discrepancy_mean <- do.call(cbind, lapply(fit_list, function(x) x$summary$theta_mean[designs[[1L]]$alpha_index]))
    reference_var <- do.call(cbind, lapply(fit_list, function(x) diag(x$summary$theta_cov)[designs[[1L]]$beta_index]))
    discrepancy_var <- do.call(cbind, lapply(fit_list, function(x) diag(x$summary$theta_cov)[designs[[1L]]$alpha_index]))
    list(reference_mean = reference_mean, discrepancy_mean = discrepancy_mean,
         reference_var = reference_var, discrepancy_var = discrepancy_var)
  }
  continuation <- if (!is.null(initial_joint_fit)) {
    app_latent_joint_validate_continuation(
      initial_joint_fit, designs, tau, likelihood, controls,
      allow_rhs_schedule_rebase = isTRUE(vb_args$joint_rhs_allow_schedule_rebase)
    )
  } else {
    NULL
  }
  if (is.null(continuation)) {
    fits <- lapply(independent_fits, app_latent_joint_extract_core_fit)
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
    previous_trace <- data.frame()
    previous_runtime_seconds <- 0
    outer_offset <- 0L
    continuation_count <- 0L
    rhs_schedule_rebase_audit <- data.frame()
  } else {
    fits <- continuation$fits
    moments <- coefficient_moments(fits)
    rhs_reference <- continuation$rhs_reference
    rhs_discrepancy <- continuation$rhs_discrepancy
    previous_trace <- continuation$trace
    previous_runtime_seconds <- continuation$previous_runtime_seconds
    outer_offset <- continuation$outer_offset
    continuation_count <- continuation$continuation_count
    rhs_schedule_rebase_audit <- continuation$rhs_schedule_rebase_audit
  }
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
  trace_new <- vector("list", outer_max)
  started <- Sys.time()
  converged <- FALSE
  converged_outer <- FALSE
  converged_inner <- FALSE
  converged_rhs <- FALSE
  rhs_gate <- list(passed = FALSE, blocks = data.frame())

  for (outer_local in seq_len(outer_max)) {
    outer <- outer_offset + outer_local
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
    reference_rhs_gate <- app_latent_joint_rhs_gate(rhs_reference, outer, "reference")
    discrepancy_rhs_gate <- app_latent_joint_rhs_gate(rhs_discrepancy, outer, "discrepancy")
    rhs_gate <- list(
      passed = reference_rhs_gate$passed && discrepancy_rhs_gate$passed,
      blocks = rbind(reference_rhs_gate$blocks, discrepancy_rhs_gate$blocks)
    )
    converged_rhs <- rhs_gate$passed
    new_theta <- do.call(cbind, lapply(fits, function(x) x$summary$theta_mean))
    change <- max(abs(new_theta - old_theta) / pmax(1, abs(old_theta)))
    converged_inner <- all(vapply(fits, function(x) isTRUE(x$vb_diagnostics$converged), logical(1L)))
    converged_outer <- outer >= outer_min && is.finite(change) && change < outer_tol
    trace_new[[outer_local]] <- data.frame(
      outer_iteration = outer,
      parameter_change = change,
      all_inner_converged = converged_inner,
      outer_tolerance_met = converged_outer,
      rhs_convergence_gate_passed = converged_rhs,
      min_rhs_tau_updates = min(rhs_gate$blocks$tau_update_count),
      max_rhs_tau_updates = max(rhs_gate$blocks$tau_update_count),
      continuation_iteration = outer_local,
      elapsed_seconds = previous_runtime_seconds +
        as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
    message(sprintf(
      "[Part4 joint %s] outer iteration %d (continuation %d/%d) change=%.6g inner=%s",
      likelihood, outer, outer_local, outer_max, change,
      paste0(converged_inner, ", rhs=", converged_rhs)
    ))
    if (converged_outer && converged_inner && converged_rhs) {
      converged <- TRUE
      trace_new <- trace_new[seq_len(outer_local)]
      break
    }
  }
  trace_new <- do.call(rbind, trace_new[vapply(trace_new, is.data.frame, logical(1L))])
  trace <- if (nrow(previous_trace)) {
    app_bind_rows_fill(list(previous_trace, trace_new))
  } else {
    trace_new
  }
  stopping_reason <- if (converged) {
    "converged_outer_inner_and_rhs"
  } else if (!converged_rhs) {
    "max_outer_iterations_rhs_gate_not_passed"
  } else if (!converged_inner && !converged_outer) {
    "max_outer_iterations_outer_and_inner_not_converged"
  } else if (!converged_inner) {
    "max_outer_iterations_inner_not_converged"
  } else {
    "max_outer_iterations_outer_tolerance_not_met"
  }
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
    converged_outer = converged_outer,
    converged_inner = converged_inner,
    converged_rhs = converged_rhs,
    stopping_reason = stopping_reason,
    rhs_convergence_diagnostics = rhs_gate$blocks,
    rhs_schedule = rhs_schedule,
    rhs_schedule_rebase_audit = rhs_schedule_rebase_audit,
    trace = trace,
    runtime_seconds = previous_runtime_seconds +
      as.numeric(difftime(Sys.time(), started, units = "secs")),
    continuation_runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    previous_outer_iterations = outer_offset,
    continuation_count = continuation_count,
    future_truth_policy = designs[[1L]]$future_truth_policy,
    ensemble_weight_contract = "each_horizon_sums_to_one",
    approximation = "mean_field_quantile_blocks_with_adjacent_rhs_coordinate_updates"
  )
}
