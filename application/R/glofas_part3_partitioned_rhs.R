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

app_glofas_part3_rhs_validate_block_state <- function(state, p, tau0 = NULL, zeta2_fixed = NULL) {
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
  if (!is.null(zeta2_fixed)) {
    observed <- as.numeric(state$zeta2_fixed %||% NA_real_)
    if (!is.finite(observed) || abs(observed - as.numeric(zeta2_fixed)) > 1.0e-14) {
      stop("Part 3 RHS warm state has an incompatible fixed slab scale.", call. = FALSE)
    }
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
      zeta2_fixed = controls$zeta2_fixed %||% NULL,
      intercept_prec = as.numeric(controls$intercept_prec)
    ),
    rhs_control = controls$rhs_control
  )
  state$e_inv_zeta2 <- if (is.null(controls$zeta2_fixed)) {
    1 / as.numeric(controls$slab_s2)
  } else {
    1 / as.numeric(controls$zeta2_fixed)
  }
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
  zeta2_fixed = NULL,
  warm_anchor = NULL,
  coefficient_mean = NULL,
  coefficient_var_diag = NULL
) {
  app_glofas_part3_rhs_validate_controls(controls)
  controls$zeta2_fixed <- zeta2_fixed
  if (!is.null(zeta2_fixed) && (length(zeta2_fixed) != 1L || !is.finite(zeta2_fixed) || zeta2_fixed <= 0)) {
    stop("Part 3 fixed RHS slab scale must be NULL or a finite positive scalar.", call. = FALSE)
  }
  K <- as.integer(K)
  p <- as.integer(p)
  tau0 <- as.numeric(tau0)
  if (K < 1L || p < 1L || !is.finite(tau0) || tau0 <= 0) {
    stop("Part 3 RHS state dimensions and tau0 must be positive.", call. = FALSE)
  }
  state <- vector("list", K)
  names(state) <- c("anchor", if (K > 1L) paste0("delta_", 2:K) else character())
  if (!is.null(warm_anchor)) {
    app_glofas_part3_rhs_validate_block_state(warm_anchor, p, tau0, zeta2_fixed)
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
    if (isTRUE(state$update_zeta %||% TRUE)) {
      state$e_inv_zeta2 <- (state$a_zeta + length(idx) / 2) /
        pmax(state$b_zeta + 0.5 * sum(e_theta2[idx]), 1.0e-12)
    }
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

app_glofas_part3_rhs_inferential_state <- function(state) {
  if (!is.list(state) || !length(state)) {
    stop("Part 3 RHS state must contain at least one block.", call. = FALSE)
  }
  out <- unlist(lapply(state, function(block) {
    c(
      as.numeric(block$e_inv_lambda2 %||% numeric()),
      as.numeric(block$e_inv_nu %||% numeric()),
      as.numeric(block$e_inv_tau2 %||% numeric()),
      as.numeric(block$e_inv_xi %||% numeric()),
      as.numeric(block$e_inv_zeta2 %||% numeric()),
      as.numeric(block$prior_precision %||% numeric())
    )
  }), use.names = FALSE)
  if (!length(out) || any(!is.finite(out))) {
    stop("Part 3 RHS inferential state is empty or non-finite.", call. = FALSE)
  }
  out
}

app_glofas_part3_rhs_change_diagnostics <- function(current, previous, floor = 1) {
  named_state <- function(state) {
    unlist(unname(Map(function(block, block_name) {
      fields <- c(
        "e_inv_lambda2", "e_inv_nu", "e_inv_tau2", "e_inv_xi",
        "e_inv_zeta2", "prior_precision"
      )
      unlist(unname(lapply(fields, function(field) {
        value <- as.numeric(block[[field]] %||% numeric())
        names(value) <- paste0(block_name, ".", field, "[", seq_along(value), "]")
        value
      })), use.names = TRUE)
    }, state, names(state))), use.names = TRUE)
  }
  current <- named_state(current)
  previous <- named_state(previous)
  if (!identical(names(current), names(previous)) || !length(current) ||
      any(!is.finite(current)) || any(!is.finite(previous))) {
    stop("Part 3 RHS inferential coordinates changed between iterations.", call. = FALSE)
  }
  relative <- abs(current - previous) / pmax(as.numeric(floor), abs(previous))
  controlling <- which.max(relative)
  coordinate <- names(relative)[[controlling]]
  parsed <- regmatches(
    coordinate,
    regexec("^([^.]+)\\.([^[]+)\\[([0-9]+)\\]$", coordinate)
  )[[1L]]
  if (length(parsed) != 4L) {
    stop(sprintf("Unable to parse Part 3 RHS coordinate: %s", coordinate), call. = FALSE)
  }
  precision <- grepl("\\.prior_precision\\[", names(relative))
  safe_max <- function(x) if (length(x)) max(x) else 0
  list(
    max_relative_change = unname(relative[[controlling]]),
    max_auxiliary_change = safe_max(relative[!precision]),
    max_precision_change = safe_max(relative[precision]),
    controlling_block = parsed[[2L]],
    controlling_component = parsed[[3L]],
    controlling_coordinate = coordinate
  )
}

app_glofas_part3_rhs_solve_fixed_moments <- function(
  state,
  coefficient_mean,
  coefficient_var_diag,
  iter,
  min_iter = 2L,
  max_iter = 50L,
  tolerance = 1.0e-4,
  consecutive_passes = 2L
) {
  min_iter <- as.integer(min_iter)
  max_iter <- as.integer(max_iter)
  consecutive_passes <- as.integer(consecutive_passes)
  tolerance <- as.numeric(tolerance)
  if (!is.finite(min_iter) || !is.finite(max_iter) || min_iter < 1L ||
      max_iter < min_iter || !is.finite(consecutive_passes) || consecutive_passes < 1L ||
      !is.finite(tolerance) || tolerance <= 0) {
    stop("Invalid fixed-moment RHS solver controls.", call. = FALSE)
  }
  coefficient_mean <- as.matrix(coefficient_mean)
  coefficient_var_diag <- as.matrix(coefficient_var_diag)
  if (!identical(dim(coefficient_mean), dim(coefficient_var_diag)) ||
      ncol(coefficient_mean) != length(state)) {
    stop("Fixed-moment RHS solver dimensions are inconsistent.", call. = FALSE)
  }

  current <- state
  trace <- vector("list", max_iter)
  global_update_enabled <- NULL
  trailing_passes <- 0L
  converged <- FALSE
  for (inner in seq_len(max_iter)) {
    previous <- current
    current <- app_glofas_part3_rhs_update(
      current,
      coefficient_mean,
      coefficient_var_diag,
      iter = iter,
      update_global = if (inner == 1L) NULL else global_update_enabled
    )
    performed <- vapply(
      current,
      function(block) isTRUE(block$last_global_update_performed),
      logical(1L)
    )
    if (inner == 1L) {
      if (length(unique(performed)) != 1L) {
        stop("RHS blocks disagree about the global-update schedule.", call. = FALSE)
      }
      global_update_enabled <- performed[[1L]]
    }
    change <- app_glofas_part3_rhs_change_diagnostics(current, previous)
    relative_change <- change$max_relative_change
    pass <- is.finite(relative_change) && relative_change <= tolerance
    trailing_passes <- if (pass) trailing_passes + 1L else 0L
    trace[[inner]] <- data.frame(
      rhs_inner_iteration = inner,
      inferential_relative_change = relative_change,
      auxiliary_relative_change = change$max_auxiliary_change,
      precision_relative_change = change$max_precision_change,
      controlling_block = change$controlling_block,
      controlling_component = change$controlling_component,
      controlling_coordinate = change$controlling_coordinate,
      global_update_enabled = isTRUE(global_update_enabled),
      convergence_pass = pass,
      trailing_consecutive_passes = trailing_passes,
      stringsAsFactors = FALSE
    )
    if (inner >= min_iter && trailing_passes >= consecutive_passes) {
      converged <- TRUE
      trace <- trace[seq_len(inner)]
      break
    }
  }
  trace <- do.call(rbind, trace[vapply(trace, is.data.frame, logical(1L))])
  list(
    state = current,
    converged = converged,
    iterations = nrow(trace),
    relative_change = tail(trace$inferential_relative_change, 1L),
    auxiliary_relative_change = tail(trace$auxiliary_relative_change, 1L),
    precision_relative_change = tail(trace$precision_relative_change, 1L),
    controlling_block = tail(trace$controlling_block, 1L),
    controlling_component = tail(trace$controlling_component, 1L),
    controlling_coordinate = tail(trace$controlling_coordinate, 1L),
    global_update_enabled = isTRUE(global_update_enabled),
    trace = trace
  )
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
