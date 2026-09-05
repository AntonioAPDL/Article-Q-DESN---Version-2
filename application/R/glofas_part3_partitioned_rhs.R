# Partitioned regularized-horseshoe helpers for the GloFAS Part 3 bridge.

app_glofas_part3_rhs_default_controls <- function(
  tau0_reference = 1,
  tau0_discrepancy = 1.0e-3,
  slab_s2 = 1,
  a_zeta = 2,
  b_zeta = 4,
  intercept_prec = 1.0e-9,
  update_every = 1L,
  freeze_tau_warmup_iters = 0L,
  min_tau_updates = 0L
) {
  list(
    tau0_reference = as.numeric(tau0_reference),
    tau0_discrepancy = as.numeric(tau0_discrepancy),
    slab_s2 = as.numeric(slab_s2),
    a_zeta = as.numeric(a_zeta),
    b_zeta = as.numeric(b_zeta),
    intercept_prec = as.numeric(intercept_prec),
    rhs_control = list(
      update_every = as.integer(update_every),
      freeze_tau_warmup_iters = as.integer(freeze_tau_warmup_iters),
      min_tau_updates = as.integer(min_tau_updates)
    )
  )
}

app_glofas_part3_rhs_validate_controls <- function(controls) {
  required <- c(
    "tau0_reference", "tau0_discrepancy", "slab_s2", "a_zeta", "b_zeta",
    "intercept_prec", "rhs_control"
  )
  missing <- setdiff(required, names(controls))
  if (length(missing)) {
    stop(sprintf("Part 3 RHS controls are missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  positive <- unlist(controls[c(
    "tau0_reference", "tau0_discrepancy", "slab_s2", "a_zeta", "b_zeta", "intercept_prec"
  )], use.names = TRUE)
  if (any(!is.finite(positive)) || any(positive <= 0)) {
    stop("Part 3 RHS scales and hyperparameters must be finite and positive.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_part3_rhs_validate_block_state <- function(state, p, tau0 = NULL) {
  p <- as.integer(p)
  if (!is.list(state) || p < 1L) stop("Invalid Part 3 RHS block state.", call. = FALSE)
  if (length(state$prior_precision %||% numeric()) != p ||
      length(state$e_inv_lambda2 %||% numeric()) != p ||
      length(state$e_inv_nu %||% numeric()) != p) {
    stop("Part 3 RHS block-state dimensions do not match the coefficient block.", call. = FALSE)
  }
  if (!identical(as.integer(state$intercept_index %||% integer()), 1L)) {
    stop("Part 3 RHS block must exempt its leading intercept.", call. = FALSE)
  }
  if (!is.null(tau0) && abs(as.numeric(state$tau0) - as.numeric(tau0)) > 1.0e-14) {
    stop("Part 3 RHS warm state has an incompatible tau0.", call. = FALSE)
  }
  if (any(!is.finite(as.numeric(state$prior_precision))) ||
      any(as.numeric(state$prior_precision) <= 0)) {
    stop("Part 3 RHS prior precision must be finite and positive.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_part3_rhs_new_block <- function(p, tau0, controls) {
  if (!exists("app_latent_rhs_state_init", mode = "function")) {
    stop("Part 3 partitioned RHS requires latent_path_vb_al.R.", call. = FALSE)
  }
  state <- app_latent_rhs_state_init(
    p = as.integer(p),
    intercept_index = 1L,
    args = list(
      tau0 = as.numeric(tau0),
      a_zeta = as.numeric(controls$a_zeta),
      b_zeta = as.numeric(controls$b_zeta),
      intercept_prec = as.numeric(controls$intercept_prec)
    ),
    rhs_control = controls$rhs_control
  )
  state$e_inv_zeta2 <- 1 / as.numeric(controls$slab_s2)
  state$prior_precision <- app_latent_rhs_prior_precision(state, as.integer(p))
  state$slab_s2_initial <- as.numeric(controls$slab_s2)
  app_glofas_part3_rhs_validate_block_state(state, p, tau0)
  state
}

app_glofas_part3_rhs_initialize <- function(
  K,
  p,
  tau0,
  controls,
  warm_anchor = NULL,
  coefficient_mean = NULL,
  coefficient_var_diag = NULL
) {
  app_glofas_part3_rhs_validate_controls(controls)
  K <- as.integer(K)
  p <- as.integer(p)
  tau0 <- as.numeric(tau0)
  if (K < 1L || p < 1L || !is.finite(tau0) || tau0 <= 0) {
    stop("Part 3 RHS state dimensions and tau0 must be positive.", call. = FALSE)
  }
  state <- vector("list", K)
  names(state) <- c("anchor", if (K > 1L) paste0("delta_", 2:K) else character())
  if (!is.null(warm_anchor)) {
    app_glofas_part3_rhs_validate_block_state(warm_anchor, p, tau0)
    state[[1L]] <- warm_anchor
    state[[1L]]$rhs_control <- app_latent_normalize_rhs_control(controls$rhs_control)
  } else {
    state[[1L]] <- app_glofas_part3_rhs_new_block(p, tau0, controls)
  }
  if (K > 1L) {
    for (kk in 2:K) state[[kk]] <- app_glofas_part3_rhs_new_block(p, tau0, controls)
  }
  if (!is.null(coefficient_mean)) {
    coefficient_mean <- as.matrix(coefficient_mean)
    coefficient_var_diag <- as.matrix(coefficient_var_diag %||% matrix(0, p, K))
    if (!identical(dim(coefficient_mean), c(p, K)) ||
        !identical(dim(coefficient_var_diag), c(p, K))) {
      stop("Initial Part 3 RHS coefficient moments have incompatible dimensions.", call. = FALSE)
    }
    state <- app_glofas_part3_rhs_update(
      state,
      coefficient_mean = coefficient_mean,
      coefficient_var_diag = coefficient_var_diag,
      iter = 0L,
      update_global = FALSE
    )
  }
  state
}

app_glofas_part3_rhs_state_update_diag <- function(
  state,
  theta_mean,
  theta_var_diag,
  iter = 1L,
  update_global = NULL
) {
  theta_mean <- as.numeric(theta_mean)
  theta_var_diag <- pmax(as.numeric(theta_var_diag), 0)
  p <- length(theta_mean)
  if (length(theta_var_diag) != p || any(!is.finite(theta_mean)) ||
      any(!is.finite(theta_var_diag))) {
    stop("Part 3 RHS diagonal moments must be finite and dimension-compatible.", call. = FALSE)
  }
  app_glofas_part3_rhs_validate_block_state(state, p)
  e_theta2 <- pmax(theta_mean^2 + theta_var_diag, .Machine$double.eps)
  idx <- as.integer(state$penalized)
  schedule <- app_latent_rhs_global_schedule(state, iter = iter, update_global = update_global)
  state$last_update_iteration <- schedule$iteration
  state$last_warmup_active <- schedule$warmup_active
  state$last_global_update_performed <- schedule$global_update_performed
  state$last_update_reason <- schedule$reason
  state$last_global_relative_change <- 0
  state$last_coefficient_l2 <- if (length(idx)) sqrt(sum(theta_mean[idx]^2)) else 0
  if (length(idx)) {
    lambda_rate <- pmax(state$e_inv_nu[idx] + 0.5 * e_theta2[idx] * state$e_inv_tau2, 1.0e-12)
    state$e_inv_lambda2[idx] <- 1 / lambda_rate
    state$e_inv_nu[idx] <- 1 / pmax(1 + state$e_inv_lambda2[idx], 1.0e-12)
    if (isTRUE(schedule$global_update_performed)) {
      old <- c(state$e_inv_tau2, state$e_inv_xi)
      tau_shape <- (length(idx) + 1) / 2
      tau_rate <- pmax(state$e_inv_xi + 0.5 * sum(e_theta2[idx] * state$e_inv_lambda2[idx]), 1.0e-12)
      state$e_inv_tau2 <- tau_shape / tau_rate
      state$e_inv_xi <- 1 / pmax(1 / state$tau0^2 + state$e_inv_tau2, 1.0e-12)
      now <- c(state$e_inv_tau2, state$e_inv_xi)
      state$last_global_relative_change <- max(abs(now - old) / pmax(1, abs(old)))
      state$tau_update_count <- as.integer(state$tau_update_count %||% 0L) + 1L
      if (!is.finite(state$first_tau_update_iter)) state$first_tau_update_iter <- schedule$iteration
      state$last_tau_update_iter <- schedule$iteration
      if (schedule$iteration > state$rhs_control$freeze_tau_warmup_iters) {
        state$has_post_warmup_tau_update <- TRUE
      }
    }
    state$e_inv_zeta2 <- (state$a_zeta + length(idx) / 2) /
      pmax(state$b_zeta + 0.5 * sum(e_theta2[idx]), 1.0e-12)
  }
  state$prior_precision <- app_latent_rhs_prior_precision(state, p)
  state
}

app_glofas_part3_rhs_update <- function(
  state,
  coefficient_mean,
  coefficient_var_diag,
  iter = 1L,
  update_global = NULL
) {
  coefficient_mean <- as.matrix(coefficient_mean)
  coefficient_var_diag <- as.matrix(coefficient_var_diag)
  K <- ncol(coefficient_mean)
  p <- nrow(coefficient_mean)
  if (!identical(dim(coefficient_var_diag), c(p, K)) || length(state) != K) {
    stop("Part 3 RHS update dimensions are inconsistent.", call. = FALSE)
  }
  state[[1L]] <- app_glofas_part3_rhs_state_update_diag(
    state[[1L]], coefficient_mean[, 1L], coefficient_var_diag[, 1L],
    iter = iter, update_global = update_global
  )
  if (K > 1L) {
    for (kk in 2:K) {
      state[[kk]] <- app_glofas_part3_rhs_state_update_diag(
        state[[kk]],
        coefficient_mean[, kk] - coefficient_mean[, kk - 1L],
        coefficient_var_diag[, kk] + coefficient_var_diag[, kk - 1L],
        iter = iter,
        update_global = update_global
      )
    }
  }
  state
}

app_glofas_part3_rhs_prior_terms <- function(state, coefficient_mean) {
  coefficient_mean <- as.matrix(coefficient_mean)
  K <- ncol(coefficient_mean)
  p <- nrow(coefficient_mean)
  if (length(state) != K) stop("Part 3 RHS prior state has the wrong number of quantile blocks.", call. = FALSE)
  precision <- lapply(state, function(x) {
    app_glofas_part3_rhs_validate_block_state(x, p)
    app_latent_rhs_prior_precision(x, p)
  })
  diagonal <- linear <- vector("list", K)
  for (kk in seq_len(K)) {
    d <- l <- numeric(p)
    if (kk == 1L) {
      d <- d + precision[[1L]]
      if (K > 1L) {
        d <- d + precision[[2L]]
        l <- l + precision[[2L]] * coefficient_mean[, 2L]
      }
    } else if (kk == K) {
      d <- d + precision[[kk]]
      l <- l + precision[[kk]] * coefficient_mean[, kk - 1L]
    } else {
      d <- d + precision[[kk]] + precision[[kk + 1L]]
      l <- l + precision[[kk]] * coefficient_mean[, kk - 1L] +
        precision[[kk + 1L]] * coefficient_mean[, kk + 1L]
    }
    diagonal[[kk]] <- pmax(d, 1.0e-12)
    linear[[kk]] <- l
  }
  list(diagonal = diagonal, linear = linear, difference_precision = precision)
}

app_glofas_part3_rhs_summary <- function(state, component) {
  rows <- lapply(seq_along(state), function(ii) {
    x <- state[[ii]]
    p <- length(x$prior_precision)
    diagnostic <- app_glofas_normal_rhs_state_diagnostics(x, p)
    cbind(
      data.frame(
        component = as.character(component),
        rhs_block = names(state)[[ii]],
        tau0 = as.numeric(x$tau0),
        intercept_exempt = identical(as.integer(x$intercept_index), 1L),
        stringsAsFactors = FALSE
      ),
      diagnostic
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_part3_rhs_partition_certificate <- function(
  p_reference,
  p_discrepancy,
  reference_state,
  discrepancy_state
) {
  p_reference <- as.integer(p_reference)
  p_discrepancy <- as.integer(p_discrepancy)
  if (p_reference < 1L || p_discrepancy < 1L) stop("Part 3 coefficient blocks must be non-empty.", call. = FALSE)
  if (length(reference_state) != length(discrepancy_state)) {
    stop("Part 3 RHS component states must use the same quantile grid.", call. = FALSE)
  }
  invisible(lapply(reference_state, app_glofas_part3_rhs_validate_block_state, p = p_reference))
  invisible(lapply(discrepancy_state, app_glofas_part3_rhs_validate_block_state, p = p_discrepancy))
  data.frame(
    schema_version = "glofas_part3_rhs_partition_v1",
    p_reference = p_reference,
    p_discrepancy = p_discrepancy,
    n_quantiles = length(reference_state),
    reference_intercept_index = 1L,
    discrepancy_intercept_index = 1L,
    overlap_count = 0L,
    all_precision_finite = all(vapply(
      c(reference_state, discrepancy_state),
      function(x) all(is.finite(x$prior_precision) & x$prior_precision > 0),
      logical(1L)
    )),
    stringsAsFactors = FALSE
  )
}
