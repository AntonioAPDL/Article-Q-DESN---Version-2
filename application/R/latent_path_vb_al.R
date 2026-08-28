# AL variational fitter for the latent-path GloFAS ensemble-likelihood model.
#
# This file implements the first executable latent-path engine in the article
# repo. It is intentionally narrower than the full theory note: AL likelihood,
# Gaussian q(theta), Gaussian q(Y_F) obtained by a linearized Delta step,
# GIG q(v_i), inverse-gamma q(sigma_Y), q(sigma_G), and ridge or
# regularized-horseshoe coefficient shrinkage. The production path keeps
# horizon-keyed future design objects, streams grouped future moments, and uses
# first-order Delta approximations for both the future-path update and
# draw-level prediction.

app_latent_al_constants <- function(p0) {
  p0 <- as.numeric(p0)
  if (!is.finite(p0) || p0 <= 0 || p0 >= 1) {
    stop("The AL quantile level p0 must be in (0, 1).", call. = FALSE)
  }
  list(
    A = (1 - 2 * p0) / (p0 * (1 - p0)),
    B = 2 / (p0 * (1 - p0))
  )
}

app_latent_ig_expectations <- function(shape, rate) {
  nm <- names(shape) %||% names(rate)
  shape <- as.numeric(shape)
  rate <- as.numeric(rate)
  if (any(!is.finite(shape)) || any(!is.finite(rate)) || any(shape <= 0) || any(rate <= 0)) {
    stop("Invalid inverse-gamma parameters in latent-path VB.", call. = FALSE)
  }
  out <- list(
    shape = shape,
    rate = rate,
    mean = rate / pmax(shape - 1, 1.0e-8),
    inv_mean = shape / rate,
    log_mean = log(rate) - digamma(shape)
  )
  if (!is.null(nm) && length(nm) == length(shape)) {
    out <- lapply(out, function(x) {
      names(x) <- nm
      x
    })
  }
  out
}

app_latent_gig_half_moments <- function(chi, psi) {
  chi <- pmax(as.numeric(chi), 1.0e-12)
  psi <- pmax(as.numeric(psi), 1.0e-12)
  z <- sqrt(chi * psi)
  list(
    mean = sqrt(chi / psi) * (1 + 1 / pmax(z, 1.0e-12)),
    inv_mean = sqrt(psi / chi),
    chi = chi,
    psi = psi
  )
}

app_latent_near_pd_inverse <- function(A, jitter = 1.0e-8) {
  A <- as.matrix(A)
  A <- (A + t(A)) / 2
  eig <- eigen(A, symmetric = TRUE)
  vals <- pmax(eig$values, jitter)
  inv <- eig$vectors %*% (t(eig$vectors) / vals)
  cov <- eig$vectors %*% (t(eig$vectors) * vals)
  list(inverse = (inv + t(inv)) / 2, repaired = (cov + t(cov)) / 2, eigenvalues = vals)
}

app_latent_solve_spd <- function(A, b, jitter = 1.0e-8) {
  A <- as.matrix(A)
  A <- (A + t(A)) / 2
  chol_result <- tryCatch(chol(A), error = function(e) NULL)
  if (!is.null(chol_result)) {
    return(list(
      mean = backsolve(chol_result, forwardsolve(t(chol_result), b)),
      cov = chol2inv(chol_result),
      precision = A,
      repaired = FALSE
    ))
  }
  eig <- eigen(A, symmetric = TRUE)
  vals <- pmax(eig$values, jitter)
  cov <- eig$vectors %*% (t(eig$vectors) / vals)
  list(
    mean = as.numeric(cov %*% b),
    cov = (cov + t(cov)) / 2,
    precision = eig$vectors %*% (t(eig$vectors) * vals),
    repaired = TRUE
  )
}

app_latent_mvn_draws <- function(mean, cov, n_draws, seed = NULL) {
  mean <- as.numeric(mean)
  cov <- as.matrix(cov)
  if (!is.null(seed)) set.seed(as.integer(seed))
  eig <- eigen((cov + t(cov)) / 2, symmetric = TRUE)
  vals <- pmax(eig$values, 0)
  Z <- matrix(stats::rnorm(n_draws * length(mean)), nrow = n_draws)
  root <- eig$vectors %*% diag(sqrt(vals), nrow = length(vals))
  sweep(Z %*% t(root), 2L, mean, "+")
}

app_latent_mvn_draws_exact <- function(mean, cov, n_draws, seed = NULL, backend = "chol_eigen_fallback") {
  mean <- as.numeric(mean)
  cov <- as.matrix(cov)
  backend <- tolower(as.character(backend %||% "chol_eigen_fallback")[[1L]])
  allowed <- c("chol_eigen_fallback", "eigen")
  if (!backend %in% allowed) {
    stop(sprintf("Unsupported latent-path MVN draw backend '%s'.", backend), call. = FALSE)
  }
  timing <- list()
  time_part <- function(step, expr) {
    start <- proc.time()[["elapsed"]]
    value <- force(expr)
    elapsed <- proc.time()[["elapsed"]] - start
    timing[[length(timing) + 1L]] <<- data.frame(
      step = step,
      elapsed_seconds = as.numeric(elapsed),
      stringsAsFactors = FALSE
    )
    value
  }
  cov_sym <- time_part("symmetrize", {
    (cov + t(cov)) / 2
  })
  if (!is.null(seed)) set.seed(as.integer(seed))
  Z <- time_part("random_normals", {
    matrix(stats::rnorm(n_draws * length(mean)), nrow = n_draws)
  })
  used_backend <- backend
  if (identical(backend, "chol_eigen_fallback")) {
    chol_root <- time_part("chol", {
      tryCatch(chol(cov_sym), error = function(e) NULL)
    })
    if (!is.null(chol_root)) {
      draws <- time_part("multiply", {
        Z %*% chol_root
      })
      out <- time_part("mean_shift", {
        sweep(draws, 2L, mean, "+")
      })
      attr(out, "backend") <- "chol"
      attr(out, "substep_timing") <- do.call(rbind, timing)
      return(out)
    }
    used_backend <- "eigen_fallback"
  }
  eig <- time_part("eigen", {
    eigen(cov_sym, symmetric = TRUE)
  })
  vals <- pmax(eig$values, 0)
  root <- time_part("root", {
    eig$vectors %*% diag(sqrt(vals), nrow = length(vals))
  })
  draws <- time_part("multiply", {
    Z %*% t(root)
  })
  out <- time_part("mean_shift", {
    sweep(draws, 2L, mean, "+")
  })
  attr(out, "backend") <- used_backend
  attr(out, "substep_timing") <- do.call(rbind, timing)
  out
}

app_latent_rhs_integer_control <- function(value, name, minimum) {
  value_num <- suppressWarnings(as.numeric(value)[[1L]])
  if (!is.finite(value_num) || value_num < minimum || abs(value_num - round(value_num)) > 1.0e-8) {
    stop(sprintf("RHS %s must be an integer greater than or equal to %d.", name, minimum), call. = FALSE)
  }
  as.integer(round(value_num))
}

app_latent_normalize_rhs_control <- function(args = NULL) {
  args <- args %||% list()
  freeze_iters <- app_latent_rhs_integer_control(
    args$freeze_tau_warmup_iters %||% 0L,
    "freeze_tau_warmup_iters",
    0L
  )
  min_tau_updates <- app_latent_rhs_integer_control(
    args$min_tau_updates %||% 0L,
    "min_tau_updates",
    0L
  )
  if (freeze_iters > 0L) min_tau_updates <- max(1L, min_tau_updates)
  list(
    freeze_tau_warmup_iters = freeze_iters,
    update_every = app_latent_rhs_integer_control(args$update_every %||% 1L, "update_every", 1L),
    min_tau_updates = min_tau_updates
  )
}

app_latent_rhs_global_schedule <- function(state, iter, update_global = NULL) {
  control <- state$rhs_control %||% app_latent_normalize_rhs_control()
  iter <- app_latent_rhs_integer_control(iter %||% 0L, "update iteration", 0L)
  warmup_active <- iter > 0L && iter <= control$freeze_tau_warmup_iters
  scheduled <- iter > 0L && !warmup_active && (iter %% control$update_every == 0L)
  forced_after_warmup <- iter > control$freeze_tau_warmup_iters &&
    control$freeze_tau_warmup_iters > 0L &&
    !isTRUE(state$has_post_warmup_tau_update)
  do_update <- if (is.null(update_global)) {
    isTRUE(scheduled || forced_after_warmup)
  } else {
    isTRUE(update_global)
  }
  if (warmup_active) do_update <- FALSE
  reason <- if (warmup_active) {
    "warmup"
  } else if (!is.null(update_global) && !isTRUE(update_global)) {
    "explicitly_disabled"
  } else if (!is.null(update_global) && isTRUE(update_global)) {
    "explicitly_enabled"
  } else if (forced_after_warmup && !scheduled) {
    "forced_after_warmup"
  } else if (scheduled) {
    "scheduled"
  } else {
    "cadence_skip"
  }
  list(
    iteration = iter,
    warmup_active = warmup_active,
    global_update_performed = do_update,
    reason = reason
  )
}

app_latent_rhs_minimum_convergence_iteration <- function(control) {
  control <- app_latent_normalize_rhs_control(control)
  if (control$min_tau_updates < 1L) return(1L)
  update_count <- 0L
  iter <- 0L
  first_after_warmup <- FALSE
  search_limit <- control$freeze_tau_warmup_iters +
    (control$min_tau_updates + 2L) * control$update_every + 2L
  while (iter < search_limit && update_count < control$min_tau_updates) {
    iter <- iter + 1L
    warmup_active <- iter <= control$freeze_tau_warmup_iters
    scheduled <- !warmup_active && (iter %% control$update_every == 0L)
    forced <- !warmup_active && control$freeze_tau_warmup_iters > 0L && !first_after_warmup
    if (scheduled || forced) {
      update_count <- update_count + 1L
      first_after_warmup <- TRUE
    }
  }
  if (update_count < control$min_tau_updates) {
    stop("Could not determine a valid RHS global-scale update schedule.", call. = FALSE)
  }
  iter + 1L
}

app_latent_rhs_state_init <- function(p, intercept_index, args, rhs_control = NULL) {
  tau0 <- as.numeric(args$tau0 %||% 1)
  a_zeta <- as.numeric(args$a_zeta %||% 2)
  b_zeta <- as.numeric(args$b_zeta %||% 4)
  if (!is.finite(tau0) || tau0 <= 0) stop("RHS tau0 must be positive.", call. = FALSE)
  penalized <- setdiff(seq_len(p), as.integer(intercept_index %||% integer(0)))
  state <- list(
    prior = "rhs_ns",
    penalized = penalized,
    intercept_index = as.integer(intercept_index %||% integer(0)),
    intercept_prec = as.numeric(args$intercept_prec %||% 1.0e-9),
    tau0 = tau0,
    a_zeta = a_zeta,
    b_zeta = b_zeta,
    e_inv_lambda2 = rep(1, p),
    e_inv_nu = rep(1, p),
    e_inv_tau2 = 1 / tau0^2,
    e_inv_xi = 1,
    e_inv_zeta2 = a_zeta / b_zeta,
    rhs_control = app_latent_normalize_rhs_control(rhs_control),
    tau_update_count = 0L,
    first_tau_update_iter = NA_integer_,
    last_tau_update_iter = NA_integer_,
    has_post_warmup_tau_update = FALSE,
    last_update_iteration = 0L,
    last_warmup_active = FALSE,
    last_global_update_performed = FALSE,
    last_update_reason = "initialization",
    last_global_relative_change = 0,
    last_coefficient_l2 = NA_real_
  )
  state$prior_precision <- app_latent_rhs_prior_precision(state, p)
  state
}

app_latent_rhs_prior_precision <- function(state, p) {
  prec <- rep(as.numeric(state$intercept_prec %||% 1.0e-9), p)
  idx <- state$penalized
  if (length(idx)) {
    prec[idx] <- as.numeric(state$e_inv_tau2) * state$e_inv_lambda2[idx] +
      as.numeric(state$e_inv_zeta2)
  }
  pmax(prec, 1.0e-12)
}

app_latent_rhs_state_update <- function(state, theta_mean, theta_cov, iter = 1L, update_global = NULL) {
  p <- length(theta_mean)
  e_theta2 <- as.numeric(theta_mean^2 + diag(theta_cov))
  idx <- state$penalized
  schedule <- app_latent_rhs_global_schedule(state, iter = iter, update_global = update_global)
  state$last_update_iteration <- schedule$iteration
  state$last_warmup_active <- schedule$warmup_active
  state$last_global_update_performed <- schedule$global_update_performed
  state$last_update_reason <- schedule$reason
  state$last_global_relative_change <- 0
  state$last_coefficient_l2 <- if (length(idx)) sqrt(sum(theta_mean[idx]^2)) else 0
  if (!length(idx)) {
    state$prior_precision <- app_latent_rhs_prior_precision(state, p)
    return(state)
  }

  lambda_shape <- 1
  lambda_rate <- pmax(state$e_inv_nu[idx] + 0.5 * e_theta2[idx] * state$e_inv_tau2, 1.0e-12)
  state$e_inv_lambda2[idx] <- lambda_shape / lambda_rate

  nu_shape <- 1
  nu_rate <- pmax(1 + state$e_inv_lambda2[idx], 1.0e-12)
  state$e_inv_nu[idx] <- nu_shape / nu_rate

  if (isTRUE(schedule$global_update_performed)) {
    old_global <- c(e_inv_tau2 = state$e_inv_tau2, e_inv_xi = state$e_inv_xi)
    tau_shape <- (length(idx) + 1) / 2
    tau_rate <- pmax(state$e_inv_xi + 0.5 * sum(e_theta2[idx] * state$e_inv_lambda2[idx]), 1.0e-12)
    state$e_inv_tau2 <- tau_shape / tau_rate

    xi_shape <- 1
    xi_rate <- pmax(1 / state$tau0^2 + state$e_inv_tau2, 1.0e-12)
    state$e_inv_xi <- xi_shape / xi_rate
    new_global <- c(e_inv_tau2 = state$e_inv_tau2, e_inv_xi = state$e_inv_xi)
    state$last_global_relative_change <- max(abs(new_global - old_global) / pmax(1, abs(old_global)))
    state$tau_update_count <- as.integer(state$tau_update_count %||% 0L) + 1L
    if (!is.finite(state$first_tau_update_iter)) state$first_tau_update_iter <- schedule$iteration
    state$last_tau_update_iter <- schedule$iteration
    if (schedule$iteration > state$rhs_control$freeze_tau_warmup_iters) {
      state$has_post_warmup_tau_update <- TRUE
    }
  }

  zeta_shape <- state$a_zeta + length(idx) / 2
  zeta_rate <- pmax(state$b_zeta + 0.5 * sum(e_theta2[idx]), 1.0e-12)
  state$e_inv_zeta2 <- zeta_shape / zeta_rate

  state$prior_precision <- app_latent_rhs_prior_precision(state, p)
  state
}

app_latent_grouped_rhs_prior_precision <- function(state, p) {
  prec <- rep(as.numeric(state$intercept_prec %||% 1.0e-9), p)
  for (group_name in names(state$global_groups)) {
    idx <- state$global_groups[[group_name]]
    prec[idx] <- as.numeric(state$e_inv_tau2[[group_name]]) * state$e_inv_lambda2[idx] +
      as.numeric(state$e_inv_zeta2)
  }
  pmax(prec, 1.0e-12)
}

app_latent_grouped_rhs_state_init <- function(p, intercept_index, args, rhs_control = NULL) {
  layout <- args$global_groups %||% NULL
  if (!is.list(layout) || !isTRUE(layout$enabled)) {
    stop("Grouped RHS initialization requires an enabled semantic group layout.", call. = FALSE)
  }
  if (!identical(as.integer(layout$p), as.integer(p))) {
    stop("Grouped RHS layout dimension does not match the coefficient block.", call. = FALSE)
  }
  intercept_index <- sort(unique(as.integer(intercept_index %||% integer())))
  if (!identical(intercept_index, sort(unique(as.integer(layout$intercept_index))))) {
    stop("Grouped RHS layout intercepts do not match the coefficient block.", call. = FALSE)
  }
  groups <- lapply(layout$groups, function(index) sort(unique(as.integer(index))))
  if (!length(groups) || is.null(names(groups)) || any(!nzchar(names(groups)))) {
    stop("Grouped RHS layout must contain named nonempty groups.", call. = FALSE)
  }
  penalized <- setdiff(seq_len(p), intercept_index)
  assigned <- unlist(groups, use.names = FALSE)
  if (any(vapply(groups, length, integer(1L)) == 0L) || anyDuplicated(assigned) ||
      !identical(sort(assigned), penalized)) {
    stop("Grouped RHS layout must partition every penalized coefficient exactly once.", call. = FALSE)
  }
  tau0 <- as.numeric(layout$tau0[names(groups)])
  names(tau0) <- names(groups)
  if (any(!is.finite(tau0) | tau0 <= 0)) {
    stop("Grouped RHS tau0 values must be finite and positive.", call. = FALSE)
  }
  a_zeta <- as.numeric(args$a_zeta %||% 2)
  b_zeta <- as.numeric(args$b_zeta %||% 4)
  state <- list(
    prior = "grouped_rhs_ns",
    penalized = penalized,
    intercept_index = intercept_index,
    intercept_prec = as.numeric(args$intercept_prec %||% 1.0e-9),
    global_groups = groups,
    group_layout_hash = as.character(layout$layout_hash %||% NA_character_),
    tau0 = tau0,
    a_zeta = a_zeta,
    b_zeta = b_zeta,
    e_inv_lambda2 = rep(1, p),
    e_inv_nu = rep(1, p),
    e_inv_tau2 = stats::setNames(1 / tau0^2, names(groups)),
    e_inv_xi = stats::setNames(rep(1, length(groups)), names(groups)),
    e_inv_zeta2 = a_zeta / b_zeta,
    rhs_control = app_latent_normalize_rhs_control(rhs_control),
    tau_update_count = 0L,
    group_tau_update_count = stats::setNames(integer(length(groups)), names(groups)),
    first_tau_update_iter = NA_integer_,
    group_first_tau_update_iter = stats::setNames(rep(NA_integer_, length(groups)), names(groups)),
    last_tau_update_iter = NA_integer_,
    group_last_tau_update_iter = stats::setNames(rep(NA_integer_, length(groups)), names(groups)),
    has_post_warmup_tau_update = FALSE,
    last_update_iteration = 0L,
    last_warmup_active = FALSE,
    last_global_update_performed = FALSE,
    last_update_reason = "initialization",
    last_global_relative_change = 0,
    last_group_global_relative_change = stats::setNames(rep(0, length(groups)), names(groups)),
    last_coefficient_l2 = NA_real_,
    last_group_coefficient_l2 = stats::setNames(rep(NA_real_, length(groups)), names(groups))
  )
  state$prior_precision <- app_latent_grouped_rhs_prior_precision(state, p)
  state
}

app_latent_grouped_rhs_state_update <- function(state, theta_mean, theta_cov, iter = 1L, update_global = NULL) {
  p <- length(theta_mean)
  if (!identical(as.integer(p), as.integer(length(state$prior_precision)))) {
    stop("Grouped RHS update coefficient dimension changed.", call. = FALSE)
  }
  e_theta2 <- as.numeric(theta_mean^2 + diag(theta_cov))
  schedule <- app_latent_rhs_global_schedule(state, iter = iter, update_global = update_global)
  state$last_update_iteration <- schedule$iteration
  state$last_warmup_active <- schedule$warmup_active
  state$last_global_update_performed <- schedule$global_update_performed
  state$last_update_reason <- schedule$reason
  state$last_global_relative_change <- 0
  state$last_group_global_relative_change[] <- 0
  state$last_coefficient_l2 <- sqrt(sum(theta_mean[state$penalized]^2))

  for (group_name in names(state$global_groups)) {
    idx <- state$global_groups[[group_name]]
    state$last_group_coefficient_l2[[group_name]] <- sqrt(sum(theta_mean[idx]^2))
    lambda_rate <- pmax(
      state$e_inv_nu[idx] + 0.5 * e_theta2[idx] * state$e_inv_tau2[[group_name]],
      1.0e-12
    )
    state$e_inv_lambda2[idx] <- 1 / lambda_rate
    state$e_inv_nu[idx] <- 1 / pmax(1 + state$e_inv_lambda2[idx], 1.0e-12)
  }

  if (isTRUE(schedule$global_update_performed)) {
    old_tau <- state$e_inv_tau2
    old_xi <- state$e_inv_xi
    for (group_name in names(state$global_groups)) {
      idx <- state$global_groups[[group_name]]
      tau_shape <- (length(idx) + 1) / 2
      tau_rate <- pmax(
        state$e_inv_xi[[group_name]] +
          0.5 * sum(e_theta2[idx] * state$e_inv_lambda2[idx]),
        1.0e-12
      )
      state$e_inv_tau2[[group_name]] <- tau_shape / tau_rate
      state$e_inv_xi[[group_name]] <- 1 / pmax(
        1 / state$tau0[[group_name]]^2 + state$e_inv_tau2[[group_name]],
        1.0e-12
      )
      relative_change <- max(abs(
        c(state$e_inv_tau2[[group_name]], state$e_inv_xi[[group_name]]) -
          c(old_tau[[group_name]], old_xi[[group_name]])
      ) / pmax(1, abs(c(old_tau[[group_name]], old_xi[[group_name]]))))
      state$last_group_global_relative_change[[group_name]] <- relative_change
      state$group_tau_update_count[[group_name]] <-
        as.integer(state$group_tau_update_count[[group_name]]) + 1L
      if (!is.finite(state$group_first_tau_update_iter[[group_name]])) {
        state$group_first_tau_update_iter[[group_name]] <- schedule$iteration
      }
      state$group_last_tau_update_iter[[group_name]] <- schedule$iteration
    }
    state$last_global_relative_change <- max(state$last_group_global_relative_change)
    state$tau_update_count <- as.integer(state$tau_update_count %||% 0L) + 1L
    if (!is.finite(state$first_tau_update_iter)) state$first_tau_update_iter <- schedule$iteration
    state$last_tau_update_iter <- schedule$iteration
    if (schedule$iteration > state$rhs_control$freeze_tau_warmup_iters) {
      state$has_post_warmup_tau_update <- TRUE
    }
  }

  idx <- state$penalized
  zeta_shape <- state$a_zeta + length(idx) / 2
  zeta_rate <- pmax(state$b_zeta + 0.5 * sum(e_theta2[idx]), 1.0e-12)
  state$e_inv_zeta2 <- zeta_shape / zeta_rate
  state$prior_precision <- app_latent_grouped_rhs_prior_precision(state, p)
  state
}

app_latent_rhs_state_init_dispatch <- function(p, intercept_index, args, rhs_control = NULL) {
  if (isTRUE((args$global_groups %||% list())$enabled)) {
    return(app_latent_grouped_rhs_state_init(p, intercept_index, args, rhs_control))
  }
  app_latent_rhs_state_init(p, intercept_index, args, rhs_control)
}

app_latent_rhs_state_update_dispatch <- function(state, theta_mean, theta_cov, iter = 1L, update_global = NULL) {
  if (identical(state$prior, "grouped_rhs_ns")) {
    return(app_latent_grouped_rhs_state_update(state, theta_mean, theta_cov, iter, update_global))
  }
  app_latent_rhs_state_update(state, theta_mean, theta_cov, iter, update_global)
}

app_latent_prior_state_combine_precision <- function(state, p) {
  if (!identical(state$prior, "block_rhs_ns")) return(state$prior_precision)
  prec <- rep(NA_real_, p)
  for (block_name in names(state$blocks)) {
    block <- state$blocks[[block_name]]
    prec[block$global_index] <- block$state$prior_precision
  }
  if (any(!is.finite(prec))) stop("Block RHS prior precision is incomplete.", call. = FALSE)
  pmax(prec, 1.0e-12)
}

app_latent_prior_block_intercepts <- function(global_index, intercept_index) {
  hit <- match(as.integer(intercept_index %||% integer(0)), as.integer(global_index))
  as.integer(hit[is.finite(hit)])
}

app_latent_prior_state_init <- function(
  p,
  prior,
  intercept_index,
  vb_args,
  beta_index = NULL,
  alpha_index = NULL
) {
  prior <- tolower(as.character(prior %||% "rhs_ns"))
  if (prior %in% c("rhs", "rhs_ns")) {
    beta_index <- as.integer(beta_index %||% integer(0))
    alpha_index <- as.integer(alpha_index %||% integer(0))
    if (length(beta_index) && length(alpha_index) &&
        identical(sort(c(beta_index, alpha_index)), seq_len(p))) {
      beta_args <- vb_args$beta_rhs %||% list()
      alpha_args <- modifyList(beta_args, vb_args$alpha_rhs %||% list())
      beta_state <- app_latent_rhs_state_init(
        p = length(beta_index),
        intercept_index = app_latent_prior_block_intercepts(beta_index, intercept_index),
        args = beta_args,
        rhs_control = vb_args$rhs %||% list()
      )
      alpha_state <- app_latent_rhs_state_init_dispatch(
        p = length(alpha_index),
        intercept_index = app_latent_prior_block_intercepts(alpha_index, intercept_index),
        args = alpha_args,
        rhs_control = vb_args$rhs %||% list()
      )
      out <- list(
        prior = "block_rhs_ns",
        blocks = list(
          beta = list(global_index = beta_index, state = beta_state),
          alpha = list(global_index = alpha_index, state = alpha_state)
        ),
        intercept_index = as.integer(intercept_index %||% integer(0))
      )
      out$prior_precision <- app_latent_prior_state_combine_precision(out, p)
      return(out)
    }
    return(app_latent_rhs_state_init(
      p,
      intercept_index,
      vb_args$beta_rhs %||% list(),
      rhs_control = vb_args$rhs %||% list()
    ))
  }
  if (identical(prior, "ridge")) {
    prec <- as.numeric((vb_args$beta_ridge %||% list())$precision %||% vb_args$ridge_precision %||% 1)
    intercept_prec <- as.numeric((vb_args$beta_rhs %||% list())$intercept_prec %||% 1.0e-9)
    out <- list(
      prior = "ridge",
      prior_precision = rep(prec, p),
      intercept_index = as.integer(intercept_index %||% integer(0))
    )
    if (length(out$intercept_index)) out$prior_precision[out$intercept_index] <- intercept_prec
    out$prior_precision <- pmax(out$prior_precision, 1.0e-12)
    return(out)
  }
  stop(sprintf("Unsupported latent-path VB prior '%s'.", prior), call. = FALSE)
}

app_latent_prior_state_update <- function(state, theta_mean, theta_cov, iter = 1L, update_global = NULL) {
  if (state$prior %in% c("rhs_ns", "grouped_rhs_ns")) {
    return(app_latent_rhs_state_update_dispatch(
      state, theta_mean, theta_cov, iter = iter, update_global = update_global
    ))
  }
  if (identical(state$prior, "block_rhs_ns")) {
    for (block_name in names(state$blocks)) {
      idx <- state$blocks[[block_name]]$global_index
      state$blocks[[block_name]]$state <- app_latent_rhs_state_update_dispatch(
        state = state$blocks[[block_name]]$state,
        theta_mean = as.numeric(theta_mean[idx]),
        theta_cov = as.matrix(theta_cov[idx, idx, drop = FALSE]),
        iter = iter,
        update_global = update_global
      )
    }
    state$prior_precision <- app_latent_prior_state_combine_precision(state, length(theta_mean))
    return(state)
  }
  state
}

app_latent_prior_rhs_states <- function(state) {
  if (state$prior %in% c("rhs_ns", "grouped_rhs_ns")) return(list(all = state))
  if (identical(state$prior, "block_rhs_ns")) {
    return(lapply(state$blocks, function(block) block$state))
  }
  list()
}

app_latent_rhs_trace_rows <- function(block, block_name, iter) {
  make_row <- function(
    label,
    group,
    idx,
    effective_tau,
    e_inv_tau2,
    e_inv_xi,
    relative_change,
    coefficient_l2,
    tau_update_count
  ) {
    local_scale <- if (length(idx)) {
      1 / sqrt(pmax(block$e_inv_lambda2[idx], 1.0e-12))
    } else numeric()
    data.frame(
      iteration = as.integer(iter),
      block = label,
      parent_block = block_name,
      global_group = group,
      group_size = length(idx),
      group_layout_hash = as.character(block$group_layout_hash %||% NA_character_),
      warmup_active = isTRUE(block$last_warmup_active),
      global_update_performed = isTRUE(block$last_global_update_performed),
      update_reason = as.character(block$last_update_reason %||% NA_character_),
      effective_tau = as.numeric(effective_tau),
      e_inv_tau2 = as.numeric(e_inv_tau2),
      e_inv_xi = as.numeric(e_inv_xi),
      e_inv_zeta2 = as.numeric(block$e_inv_zeta2),
      global_relative_change = as.numeric(relative_change),
      coefficient_l2 = as.numeric(coefficient_l2),
      local_scale_median = if (length(local_scale)) stats::median(local_scale) else NA_real_,
      local_scale_max = if (length(local_scale)) max(local_scale) else NA_real_,
      tau_update_count = as.integer(tau_update_count),
      stringsAsFactors = FALSE
    )
  }
  if (!identical(block$prior, "grouped_rhs_ns")) {
    idx <- block$penalized
    return(make_row(
      block_name, "legacy_single", idx,
      sqrt(1 / pmax(as.numeric(block$e_inv_tau2), 1.0e-12)),
      block$e_inv_tau2, block$e_inv_xi,
      block$last_global_relative_change %||% NA_real_,
      block$last_coefficient_l2 %||% NA_real_,
      block$tau_update_count %||% 0L
    ))
  }
  rows <- list(make_row(
    block_name, "all", block$penalized, NA_real_, NA_real_, NA_real_,
    block$last_global_relative_change %||% NA_real_,
    block$last_coefficient_l2 %||% NA_real_,
    block$tau_update_count %||% 0L
  ))
  for (group_name in names(block$global_groups)) {
    rows[[length(rows) + 1L]] <- make_row(
      paste(block_name, group_name, sep = "."), group_name,
      block$global_groups[[group_name]],
      sqrt(1 / pmax(block$e_inv_tau2[[group_name]], 1.0e-12)),
      block$e_inv_tau2[[group_name]], block$e_inv_xi[[group_name]],
      block$last_group_global_relative_change[[group_name]],
      block$last_group_coefficient_l2[[group_name]],
      block$group_tau_update_count[[group_name]]
    )
  }
  do.call(rbind, rows)
}

app_latent_prior_rhs_trace <- function(state, iter) {
  states <- app_latent_prior_rhs_states(state)
  if (!length(states)) return(data.frame())
  rows <- lapply(names(states), function(block_name) {
    app_latent_rhs_trace_rows(states[[block_name]], block_name, iter)
  })
  do.call(rbind, rows)
}

app_latent_rhs_gate_rows <- function(block, block_name, iter) {
  control <- block$rhs_control %||% app_latent_normalize_rhs_control()
  required <- control$min_tau_updates
  gate_row <- function(label, group, update_count, first_update) {
    enough_updates <- as.integer(update_count %||% 0L) >= required
    needs_response <- required > 0L || control$freeze_tau_warmup_iters > 0L
    coefficient_response <- !needs_response ||
      (is.finite(first_update) && as.integer(iter) > first_update)
    data.frame(
      block = label,
      parent_block = block_name,
      global_group = group,
      enough_tau_updates = enough_updates,
      coefficient_response_after_release = coefficient_response,
      passed = enough_updates && coefficient_response,
      stringsAsFactors = FALSE
    )
  }
  if (!identical(block$prior, "grouped_rhs_ns")) {
    return(gate_row(
      block_name, "legacy_single", block$tau_update_count %||% 0L,
      block$first_tau_update_iter %||% NA_integer_
    ))
  }
  group_rows <- lapply(names(block$global_groups), function(group_name) {
    gate_row(
      paste(block_name, group_name, sep = "."), group_name,
      block$group_tau_update_count[[group_name]],
      block$group_first_tau_update_iter[[group_name]]
    )
  })
  groups <- do.call(rbind, group_rows)
  aggregate <- data.frame(
    block = block_name,
    parent_block = block_name,
    global_group = "all",
    enough_tau_updates = all(groups$enough_tau_updates),
    coefficient_response_after_release = all(groups$coefficient_response_after_release),
    passed = all(groups$passed),
    stringsAsFactors = FALSE
  )
  rbind(aggregate, groups)
}

app_latent_prior_rhs_gate <- function(state, iter) {
  states <- app_latent_prior_rhs_states(state)
  if (!length(states)) return(list(passed = TRUE, blocks = data.frame()))
  rows <- lapply(names(states), function(block_name) {
    app_latent_rhs_gate_rows(states[[block_name]], block_name, iter)
  })
  blocks <- do.call(rbind, rows)
  list(passed = all(blocks$passed), blocks = blocks)
}

app_latent_rhs_diagnostic_rows <- function(block, block_name, gate_rows) {
  control <- block$rhs_control
  make_row <- function(label, group, update_count, first_update, last_update, effective_tau, e_inv_tau2, e_inv_xi, coefficient_l2) {
    gate_row <- gate_rows[gate_rows$block == label, , drop = FALSE]
    data.frame(
      block = label,
      parent_block = block_name,
      global_group = group,
      group_layout_hash = as.character(block$group_layout_hash %||% NA_character_),
      freeze_tau_warmup_iters = control$freeze_tau_warmup_iters,
      update_every = control$update_every,
      min_tau_updates = control$min_tau_updates,
      tau_update_count = as.integer(update_count %||% 0L),
      first_tau_update_iter = as.integer(first_update %||% NA_integer_),
      last_tau_update_iter = as.integer(last_update %||% NA_integer_),
      effective_tau = as.numeric(effective_tau),
      e_inv_tau2 = as.numeric(e_inv_tau2),
      e_inv_xi = as.numeric(e_inv_xi),
      coefficient_l2 = as.numeric(coefficient_l2 %||% NA_real_),
      enough_tau_updates = gate_row$enough_tau_updates[[1L]],
      coefficient_response_after_release = gate_row$coefficient_response_after_release[[1L]],
      gate_passed = gate_row$passed[[1L]],
      stringsAsFactors = FALSE
    )
  }
  if (!identical(block$prior, "grouped_rhs_ns")) {
    return(make_row(
      block_name, "legacy_single", block$tau_update_count,
      block$first_tau_update_iter, block$last_tau_update_iter,
      sqrt(1 / pmax(as.numeric(block$e_inv_tau2), 1.0e-12)),
      block$e_inv_tau2, block$e_inv_xi, block$last_coefficient_l2
    ))
  }
  rows <- list(make_row(
    block_name, "all", block$tau_update_count,
    block$first_tau_update_iter, block$last_tau_update_iter,
    NA_real_, NA_real_, NA_real_, block$last_coefficient_l2
  ))
  for (group_name in names(block$global_groups)) {
    rows[[length(rows) + 1L]] <- make_row(
      paste(block_name, group_name, sep = "."), group_name,
      block$group_tau_update_count[[group_name]],
      block$group_first_tau_update_iter[[group_name]],
      block$group_last_tau_update_iter[[group_name]],
      sqrt(1 / pmax(block$e_inv_tau2[[group_name]], 1.0e-12)),
      block$e_inv_tau2[[group_name]], block$e_inv_xi[[group_name]],
      block$last_group_coefficient_l2[[group_name]]
    )
  }
  do.call(rbind, rows)
}

app_latent_prior_rhs_diagnostics <- function(state, iter) {
  states <- app_latent_prior_rhs_states(state)
  gate <- app_latent_prior_rhs_gate(state, iter)
  if (!length(states)) {
    return(list(
      active = FALSE,
      convergence_gate_passed = TRUE,
      minimum_convergence_iteration = 1L,
      blocks = data.frame()
    ))
  }
  rows <- lapply(names(states), function(block_name) {
    block <- states[[block_name]]
    app_latent_rhs_diagnostic_rows(block, block_name, gate$blocks)
  })
  controls <- lapply(states, function(block) block$rhs_control)
  list(
    active = TRUE,
    convergence_gate_passed = gate$passed,
    minimum_convergence_iteration = max(vapply(controls, app_latent_rhs_minimum_convergence_iteration, integer(1L))),
    blocks = do.call(rbind, rows)
  )
}

app_latent_source_sigma_init <- function(source, prior_sigma) {
  source <- factor(as.character(source), levels = c("Y", "G"))
  a0 <- as.numeric(prior_sigma$a %||% 2)
  b0 <- as.numeric(prior_sigma$b %||% 1)
  tab <- table(source)
  shape <- a0 + 1.5 * as.numeric(tab[c("Y", "G")])
  names(shape) <- c("Y", "G")
  rate <- rep(b0 + 1, 2L)
  names(rate) <- c("Y", "G")
  app_latent_ig_expectations(shape, rate)
}

app_latent_future_moment_strategy <- function(vb_args = list()) {
  strategy <- tolower(as.character(vb_args$future_moment_strategy %||% "streamed_grouped"))
  allowed <- c("streamed_grouped", "dense_debug")
  if (!strategy %in% allowed) {
    stop(sprintf("Unsupported latent-path future moment strategy '%s'.", strategy), call. = FALSE)
  }
  strategy
}

app_latent_future_objective_strategy <- function(vb_args = list()) {
  strategy <- tolower(as.character(vb_args$future_objective_strategy %||% "grouped"))
  allowed <- c("grouped", "ungrouped_debug")
  if (!strategy %in% allowed) {
    stop(sprintf("Unsupported latent-path future objective strategy '%s'.", strategy), call. = FALSE)
  }
  strategy
}

app_latent_future_update_strategy <- function(vb_args = list()) {
  strategy <- tolower(as.character(vb_args$future_update_strategy %||% "linearized_delta"))
  allowed <- c("linearized_delta", "bfgs_grouped_debug")
  if (!strategy %in% allowed) {
    stop(sprintf("Unsupported latent-path future update strategy '%s'.", strategy), call. = FALSE)
  }
  strategy
}

app_latent_default_chunking_control <- function() {
  list(
    enabled = FALSE,
    mode = "exact",
    chunk_size = NULL,
    order = "sequential",
    trace = FALSE
  )
}

app_latent_normalize_chunking_control <- function(chunking = NULL) {
  cfg <- app_latent_default_chunking_control()
  if (is.null(chunking)) return(cfg)
  if (!is.list(chunking)) stop("Latent-path VB chunking control must be a list.", call. = FALSE)
  for (nm in names(chunking)) cfg[[nm]] <- chunking[[nm]]
  cfg$enabled <- isTRUE(cfg$enabled)
  cfg$mode <- tolower(as.character(cfg$mode %||% "exact"))
  if (!identical(cfg$mode, "exact")) {
    stop("Latent-path VB chunking mode must be 'exact'.", call. = FALSE)
  }
  if (is.null(cfg$chunk_size) || length(cfg$chunk_size) == 0L || is.na(cfg$chunk_size[[1L]])) {
    cfg$chunk_size <- NULL
  } else {
    cfg$chunk_size <- as.integer(cfg$chunk_size[[1L]])
    if (!is.finite(cfg$chunk_size) || cfg$chunk_size < 1L) {
      stop("Latent-path VB chunk_size must be NULL or a positive integer.", call. = FALSE)
    }
  }
  cfg$order <- tolower(as.character(cfg$order %||% "sequential"))
  if (!identical(cfg$order, "sequential")) {
    stop("Latent-path VB chunking order must be 'sequential'.", call. = FALSE)
  }
  cfg$trace <- isTRUE(cfg$trace)
  cfg
}

app_latent_make_row_chunks <- function(n, chunk_size = NULL) {
  n <- as.integer(n)[[1L]]
  if (!is.finite(n) || n < 0L) stop("Chunk row count must be a non-negative integer.", call. = FALSE)
  if (!n) return(list(integer(0)))
  if (is.null(chunk_size) || length(chunk_size) == 0L || is.na(chunk_size[[1L]])) {
    chunk_size <- n
  } else {
    chunk_size <- as.integer(chunk_size[[1L]])
    if (!is.finite(chunk_size) || chunk_size < 1L) {
      stop("Chunk size must be NULL or a positive integer.", call. = FALSE)
    }
  }
  starts <- seq.int(1L, n, by = chunk_size)
  lapply(starts, function(i) seq.int(i, min(n, i + chunk_size - 1L)))
}

app_latent_make_source_row_chunks <- function(source, chunk_size = NULL, source_levels = c("Y", "G")) {
  source <- as.character(source)
  if (!length(source)) return(list())
  out <- list()
  for (src in source_levels) {
    src_idx <- which(source == src)
    if (!length(src_idx)) next
    local_chunks <- app_latent_make_row_chunks(length(src_idx), chunk_size)
    for (chunk in local_chunks) {
      if (!length(chunk)) next
      out[[length(out) + 1L]] <- list(source = src, index = src_idx[chunk])
    }
  }
  out
}

app_latent_normalize_source_chunks <- function(source, chunks = NULL) {
  if (is.null(chunks)) return(app_latent_make_source_row_chunks(source))
  if (!length(chunks)) return(list())
  first <- chunks[[1L]]
  if (is.list(first) && all(c("source", "index") %in% names(first))) return(chunks)
  source <- as.character(source)
  out <- list()
  for (chunk in chunks) {
    if (!length(chunk)) next
    for (src in c("Y", "G")) {
      idx <- chunk[source[chunk] == src]
      if (!length(idx)) next
      out[[length(out) + 1L]] <- list(source = src, index = idx)
    }
  }
  out
}

app_latent_future_g_index <- function(future) {
  idx <- future$g_future_index %||% NULL
  if (is.null(idx) && !is.null(future$row_info_g) && "future_index" %in% names(future$row_info_g)) {
    idx <- future$row_info_g$future_index
  }
  idx <- as.integer(idx)
  if (!length(idx) || any(!is.finite(idx))) {
    stop("Latent-path future object is missing a finite GloFAS future-index vector.", call. = FALSE)
  }
  idx
}

app_latent_future_H_g_key <- function(future) {
  if (!is.null(future$H_g_key)) return(as.matrix(future$H_g_key))
  H_g <- as.matrix(future$H_g %||% NULL)
  idx <- app_latent_future_g_index(future)
  H <- nrow(as.matrix(future$H_y))
  first <- match(seq_len(H), idx)
  if (any(is.na(first))) {
    stop("Expanded GloFAS design does not contain every future horizon.", call. = FALSE)
  }
  H_g[first, , drop = FALSE]
}

app_latent_future_J_g_key <- function(future) {
  if (!is.null(future$J_g_key)) return(future$J_g_key)
  J_g <- future$J_g %||% NULL
  if (is.null(J_g)) stop("Latent-path future object is missing GloFAS Jacobians.", call. = FALSE)
  idx <- app_latent_future_g_index(future)
  H <- nrow(as.matrix(future$H_y))
  first <- match(seq_len(H), idx)
  if (any(is.na(first))) {
    stop("Expanded GloFAS Jacobians do not contain every future horizon.", call. = FALSE)
  }
  J_g[first]
}

app_latent_future_H_g_expanded <- function(future) {
  if (!is.null(future$H_g)) return(as.matrix(future$H_g))
  H_key <- app_latent_future_H_g_key(future)
  H_key[app_latent_future_g_index(future), , drop = FALSE]
}

app_latent_future_J_g_expanded <- function(future) {
  if (!is.null(future$J_g)) return(future$J_g)
  J_key <- app_latent_future_J_g_key(future)
  lapply(app_latent_future_g_index(future), function(i) J_key[[i]])
}

app_latent_trace_S_theta <- function(h, J, y_cov, theta_second) {
  h <- as.numeric(h)
  out <- as.numeric(crossprod(h, theta_second %*% h))
  J <- as.matrix(J)
  if (nrow(J) && ncol(J) && any(J != 0) && any(y_cov != 0)) {
    out <- out + sum(y_cov * crossprod(J, theta_second %*% J))
  }
  out
}

app_latent_quad_theta <- function(h, theta_mean, theta_cov) {
  h <- as.numeric(h)
  theta_mean <- as.numeric(theta_mean)
  as.numeric(crossprod(h, theta_cov %*% h)) + sum(h * theta_mean)^2
}

app_latent_quad_theta_rows <- function(H, theta_mean, theta_cov) {
  H <- as.matrix(H)
  theta_mean <- as.numeric(theta_mean)
  theta_cov <- as.matrix(theta_cov)
  rowSums((H %*% theta_cov) * H) + as.numeric(H %*% theta_mean)^2
}

app_latent_jacobian_trace_theta <- function(J, y_cov, theta_mean, theta_cov) {
  J <- as.matrix(J)
  if (!nrow(J) || !ncol(J) || !any(J != 0) || !any(y_cov != 0)) return(0)
  theta_mean <- as.numeric(theta_mean)
  theta_cov <- as.matrix(theta_cov)
  J_cov <- theta_cov %*% J
  cov_part <- sum(y_cov * crossprod(J, J_cov))
  j_mean <- as.numeric(crossprod(J, theta_mean))
  mean_part <- as.numeric(crossprod(j_mean, y_cov %*% j_mean))
  cov_part + mean_part
}

app_latent_trace_S_theta_parts <- function(h, J, y_cov, theta_mean, theta_cov) {
  h <- as.numeric(h)
  theta_mean <- as.numeric(theta_mean)
  theta_cov <- as.matrix(theta_cov)
  out <- app_latent_quad_theta(h, theta_mean, theta_cov)
  out + app_latent_jacobian_trace_theta(J, y_cov, theta_mean, theta_cov)
}

app_latent_future_has_paired_jacobians <- function(future) {
  if (!isTRUE(future$paired_future_jacobian) ||
      length(future$J_y) != length(future$J_g_key)) {
    return(FALSE)
  }
  all(vapply(seq_along(future$J_y), function(h) {
    identical(
      unname(as.matrix(future$J_y[[h]])),
      unname(as.matrix(future$J_g_key[[h]]))
    )
  }, logical(1L)))
}

app_latent_add_S_precision <- function(precision, coeff, h, J, y_cov) {
  coeff <- as.numeric(coeff)
  if (!is.finite(coeff) || abs(coeff) <= 0) return(precision)
  h <- as.numeric(h)
  precision <- precision + coeff * tcrossprod(h)
  J <- as.matrix(J)
  if (nrow(J) && ncol(J) && any(J != 0) && any(y_cov != 0)) {
    precision <- precision + coeff * (J %*% y_cov %*% t(J))
  }
  precision
}

app_latent_add_J_precision <- function(precision, coeff, J, y_cov) {
  coeff <- as.numeric(coeff)
  if (!is.finite(coeff) || abs(coeff) <= 0) return(precision)
  J <- as.matrix(J)
  if (nrow(J) && ncol(J) && any(J != 0) && any(y_cov != 0)) {
    precision <- precision + coeff * (J %*% y_cov %*% t(J))
  }
  precision
}

app_latent_row_moments_dense_debug <- function(design, y_mean, y_cov, theta_mean, theta_cov) {
  future <- design$future_builder(y_mean)
  H_fixed <- as.matrix(design$H_fixed)
  z_fixed <- as.numeric(design$z_fixed)
  source_fixed <- as.character(design$source_fixed)
  p <- ncol(H_fixed)
  fixed_mean <- as.numeric(H_fixed %*% theta_mean)
  fixed_cov <- H_fixed %*% theta_cov
  fixed_second <- fixed_mean^2 + rowSums(fixed_cov * H_fixed)
  fixed <- list(
    H = H_fixed,
    z = z_fixed,
    source = source_fixed,
    R = pmax(z_fixed^2 - 2 * z_fixed * fixed_mean + fixed_second, 1.0e-12),
    e = z_fixed - fixed_mean,
    n = nrow(H_fixed)
  )
  theta_second <- theta_cov + tcrossprod(theta_mean)

  rows <- list()
  k <- 1L
  add_row <- function(z_mean, z_second, h_mean, S, b, source, row_info, is_future, future_index = NA_integer_) {
    h_mean <- as.numeric(h_mean)
    S <- as.matrix(S)
    b <- as.numeric(b)
    R <- as.numeric(z_second - 2 * sum(b * theta_mean) + sum(S * theta_second))
    e <- as.numeric(z_mean - sum(h_mean * theta_mean))
    rows[[k]] <<- list(
      z_mean = z_mean,
      z_second = z_second,
      h_mean = h_mean,
      S = S,
      b = b,
      source = as.character(source),
      row_info = row_info,
      is_future = is_future,
      future_index = future_index,
      R = max(R, 1.0e-12),
      e = e
    )
    k <<- k + 1L
  }

  H_y <- as.matrix(future$H_y)
  H_g <- app_latent_future_H_g_expanded(future)
  J_g <- app_latent_future_J_g_expanded(future)
  if (ncol(H_y) != p || ncol(H_g) != p) {
    stop("Future latent-path design has incompatible column count.", call. = FALSE)
  }
  for (h in seq_len(nrow(H_y))) {
    J <- as.matrix(future$J_y[[h]])
    if (!all(dim(J) == c(p, length(y_mean)))) {
      stop("Future Y Jacobian has incompatible dimensions.", call. = FALSE)
    }
    mu_z <- y_mean[[h]]
    S <- tcrossprod(H_y[h, ]) + J %*% y_cov %*% t(J)
    b <- H_y[h, ] * mu_z + as.numeric(J %*% y_cov[, h, drop = FALSE])
    add_row(
      z_mean = mu_z,
      z_second = mu_z^2 + y_cov[h, h],
      h_mean = H_y[h, ],
      S = S,
      b = b,
      source = "Y",
      row_info = future$row_info_y[h, , drop = FALSE],
      is_future = TRUE,
      future_index = h
    )
  }
  for (i in seq_len(nrow(H_g))) {
    hidx <- as.integer(future$row_info_g$future_index[[i]])
    J <- as.matrix(J_g[[i]])
    S <- tcrossprod(H_g[i, ]) + J %*% y_cov %*% t(J)
    z <- future$z_g[[i]]
    add_row(
      z_mean = z,
      z_second = z^2,
      h_mean = H_g[i, ],
      S = S,
      b = H_g[i, ] * z,
      source = "G",
      row_info = future$row_info_g[i, , drop = FALSE],
      is_future = TRUE,
      future_index = hidx
    )
  }

  list(
    fixed = fixed,
    rows = rows,
    future = future,
    strategy = "dense_debug",
    source = factor(c(source_fixed, vapply(rows, `[[`, character(1L), "source")), levels = c("Y", "G"))
  )
}

app_latent_pairing_certificate_hash <- function(certificate) {
  payload <- certificate
  payload$contract_hash <- NULL
  app_latent_path_contract_hash(payload, prefix = "latent_fixed_pairing_")
}

app_latent_pairing_certificate <- function(
  X_beta_stack,
  source,
  beta_index,
  alpha_index,
  feature_names = NULL,
  tol = 0,
  optimization_enabled = TRUE
) {
  source <- as.character(source)
  y_index <- which(source == "Y")
  g_index <- which(source == "G")
  paired <- length(y_index) > 0L && length(y_index) == length(g_index)
  if (isTRUE(paired)) {
    lhs <- as.matrix(X_beta_stack[y_index, , drop = FALSE])
    rhs <- as.matrix(X_beta_stack[g_index, , drop = FALSE])
    paired <- if (tol <= 0) {
      identical(unname(lhs), unname(rhs))
    } else {
      isTRUE(all.equal(lhs, rhs, tolerance = tol, check.attributes = FALSE))
    }
  }
  payload <- list(
    schema_version = "latent_path_fixed_pairing_v1",
    paired_beta_rows = isTRUE(paired),
    n_y = length(y_index),
    n_g = length(g_index),
    n_beta = ncol(as.matrix(X_beta_stack)),
    beta_index = as.integer(beta_index),
    alpha_index = as.integer(alpha_index),
    feature_names = as.character(feature_names %||% character()),
    y_feature_rows = seq_along(y_index),
    g_feature_rows = seq_along(g_index),
    optimization_enabled = isTRUE(optimization_enabled),
    construction = "validated_equal_ordered_beta_rows",
    beta_rows_hash = if (isTRUE(paired)) {
      app_latent_path_contract_hash(
        unname(lhs),
        prefix = "latent_fixed_paired_beta_rows_"
      )
    } else {
      NA_character_
    }
  )
  payload$contract_hash <- app_latent_pairing_certificate_hash(payload)
  payload
}

app_latent_pairing_certificate_valid <- function(certificate, block = NULL) {
  if (is.null(certificate) ||
      !identical(certificate$schema_version, "latent_path_fixed_pairing_v1") ||
      !nzchar(as.character(certificate$contract_hash %||% "")) ||
      !identical(
        as.character(certificate$contract_hash),
        app_latent_pairing_certificate_hash(certificate)
      )) {
    return(FALSE)
  }
  if (isTRUE(certificate$paired_beta_rows) &&
      !nzchar(as.character(certificate$beta_rows_hash %||% ""))) {
    return(FALSE)
  }
  if (is.null(block)) return(TRUE)
  if (!identical(as.integer(certificate$n_y), as.integer(length(block$y_index))) ||
      !identical(as.integer(certificate$n_g), as.integer(length(block$g_index))) ||
      !identical(as.integer(certificate$n_beta), as.integer(ncol(block$X_beta_stack))) ||
      !identical(as.integer(certificate$beta_index), as.integer(block$beta_index)) ||
      !identical(as.integer(certificate$alpha_index), as.integer(block$alpha_index))) {
    return(FALSE)
  }
  if (length(certificate$feature_names) && length(block$feature_names) &&
      !identical(as.character(certificate$feature_names), as.character(block$feature_names))) {
    return(FALSE)
  }
  TRUE
}

app_latent_pairing_certificate_matches_block <- function(certificate, block) {
  if (!app_latent_pairing_certificate_valid(certificate, block = block)) return(FALSE)
  if (!isTRUE(certificate$paired_beta_rows)) return(TRUE)
  y_idx <- block$y_index
  g_idx <- block$g_index
  if (!length(y_idx) || length(y_idx) != length(g_idx)) return(FALSE)
  lhs <- unname(as.matrix(block$X_beta_stack[y_idx, , drop = FALSE]))
  rhs <- unname(as.matrix(block$X_beta_stack[g_idx, , drop = FALSE]))
  if (!identical(lhs, rhs)) return(FALSE)
  identical(
    as.character(certificate$beta_rows_hash),
    app_latent_path_contract_hash(
      lhs,
      prefix = "latent_fixed_paired_beta_rows_"
    )
  )
}

app_latent_fixed_block_design <- function(design = NULL, fixed = NULL, verify_dense = TRUE, tol = 1.0e-10) {
  source <- NULL
  beta_index <- NULL
  alpha_index <- NULL
  H <- NULL
  X_beta <- NULL
  X_alpha <- NULL
  pairing_certificate <- NULL
  if (!is.null(fixed) && !is.null(fixed$block)) {
    block <- fixed$block
    source <- as.character(block$source)
    beta_index <- as.integer(block$beta_index)
    alpha_index <- as.integer(block$alpha_index)
    X_beta <- as.matrix(block$X_beta_stack)
    X_alpha <- as.matrix(block$X_alpha_stack)
    pairing_certificate <- block$pairing_certificate %||% NULL
    H <- if (!is.null(fixed$H)) as.matrix(fixed$H) else NULL
  } else if (!is.null(design)) {
    source <- as.character(design$source_fixed)
    beta_index <- as.integer(design$beta_index %||% integer(0))
    alpha_index <- as.integer(design$alpha_index %||% integer(0))
    H <- if (!is.null(design$H_fixed)) as.matrix(design$H_fixed) else NULL
    pairing_certificate <- design$fixed_pairing_certificate %||% NULL
    if (!is.null(design$X_beta_stack)) {
      X_beta <- as.matrix(design$X_beta_stack)
    } else if (!is.null(design$X_beta) && !is.null(design$row_info_fixed$feature_row)) {
      X_beta <- as.matrix(design$X_beta[as.integer(design$row_info_fixed$feature_row), , drop = FALSE])
    } else if (!is.null(H) && length(beta_index)) {
      X_beta <- H[, beta_index, drop = FALSE]
    }
    if (!is.null(design$X_alpha_stack)) {
      X_alpha <- as.matrix(design$X_alpha_stack)
    } else if (!is.null(design$X_alpha) && !is.null(design$row_info_fixed$feature_row)) {
      X_alpha <- as.matrix(design$X_alpha[as.integer(design$row_info_fixed$feature_row), , drop = FALSE])
    } else if (!is.null(H) && length(alpha_index)) {
      X_alpha <- H[, alpha_index, drop = FALSE]
    }
  }
  if (!length(source) || !length(beta_index) || !length(alpha_index)) return(NULL)
  if (is.null(X_beta) || is.null(X_alpha)) return(NULL)
  X_beta <- as.matrix(X_beta)
  X_alpha <- as.matrix(X_alpha)
  storage.mode(X_beta) <- "double"
  storage.mode(X_alpha) <- "double"
  n <- length(source)
  if (nrow(X_beta) != n || nrow(X_alpha) != n) return(NULL)
  if (ncol(X_beta) != length(beta_index) || ncol(X_alpha) != length(alpha_index)) return(NULL)
  if (any(!source %in% c("Y", "G"))) return(NULL)
  p <- max(c(beta_index, alpha_index))
  if (!identical(sort(c(beta_index, alpha_index)), seq_len(p))) return(NULL)
  if (!is.null(H)) {
    H <- as.matrix(H)
    storage.mode(H) <- "double"
    if (nrow(H) != n || ncol(H) != p) return(NULL)
    if (isTRUE(verify_dense)) {
      y_index <- which(source == "Y")
      g_index <- which(source == "G")
      if (!isTRUE(all.equal(H[, beta_index, drop = FALSE], X_beta, tolerance = tol, check.attributes = FALSE))) return(NULL)
      if (length(g_index) &&
          !isTRUE(all.equal(
            H[g_index, alpha_index, drop = FALSE],
            X_alpha[g_index, , drop = FALSE],
            tolerance = tol,
            check.attributes = FALSE
          ))) {
        return(NULL)
      }
      if (length(y_index) && any(abs(H[y_index, alpha_index, drop = FALSE]) > tol)) return(NULL)
    }
  }
  list(
    source = source,
    y_index = which(source == "Y"),
    g_index = which(source == "G"),
    X_beta_stack = X_beta,
    X_alpha_stack = X_alpha,
    beta_index = beta_index,
    alpha_index = alpha_index,
    feature_names = if (!is.null(H) && !is.null(colnames(H))) colnames(H) else NULL,
    pairing_certificate = pairing_certificate,
    p = p,
    n = n
  )
}

app_latent_diagonal_values <- function(A, tol = 0) {
  A <- as.matrix(A)
  if (nrow(A) != ncol(A)) return(NULL)
  off <- A
  diag(off) <- 0
  if (any(abs(off) > tol)) return(NULL)
  diag(A)
}

app_latent_fixed_block_has_paired_beta_rows <- function(block, tol = 1.0e-10) {
  certificate <- block$pairing_certificate %||% NULL
  if (!is.null(certificate)) {
    if (!app_latent_pairing_certificate_valid(certificate, block = block)) return(FALSE)
    if (identical(certificate$optimization_enabled, FALSE)) return(FALSE)
    if (!isTRUE(certificate$paired_beta_rows)) return(FALSE)
    return(TRUE)
  }
  y_idx <- block$y_index
  g_idx <- block$g_index
  if (!length(y_idx) || length(y_idx) != length(g_idx)) return(FALSE)
  isTRUE(all.equal(
    block$X_beta_stack[y_idx, , drop = FALSE],
    block$X_beta_stack[g_idx, , drop = FALSE],
    tolerance = tol,
    check.attributes = FALSE
  ))
}

app_latent_weighted_crossprod <- function(X, Y = X, w, symmetric = identical(X, Y), method = NULL) {
  X <- as.matrix(X)
  Y <- as.matrix(Y)
  w <- as.numeric(w)
  if (nrow(X) != nrow(Y) || nrow(X) != length(w)) {
    stop("Weighted crossproduct inputs are not row aligned.", call. = FALSE)
  }
  if (any(!is.finite(w))) stop("Weighted crossproduct weights must be finite.", call. = FALSE)
  method <- tolower(as.character(method %||% getOption(
    "qdesn.latent.weighted_crossprod",
    "multiply"
  ))[[1L]])
  if (identical(method, "sqrt") && isTRUE(symmetric) && all(w >= 0)) {
    Xw <- X * sqrt(w)
    return(crossprod(Xw))
  }
  if (!identical(method, "multiply")) {
    stop(sprintf("Unsupported weighted crossproduct method '%s'.", method), call. = FALSE)
  }
  crossprod(X, Y * w)
}

app_latent_substep_timer <- function(enabled = FALSE) {
  timing <- list()
  list(
    time = function(step, expr) {
      if (!isTRUE(enabled)) return(force(expr))
      start <- proc.time()[["elapsed"]]
      value <- force(expr)
      elapsed <- proc.time()[["elapsed"]] - start
      timing[[length(timing) + 1L]] <<- data.frame(
        step = step,
        elapsed_seconds = as.numeric(elapsed),
        stringsAsFactors = FALSE
      )
      value
    },
    collect = function() {
      if (!length(timing)) return(data.frame(step = character(), elapsed_seconds = numeric()))
      do.call(rbind, timing)
    }
  )
}

app_latent_fixed_row_moments_block <- function(block, z_fixed, theta_mean, theta_cov, profile_substeps = FALSE) {
  if (is.null(block)) return(NULL)
  timer <- app_latent_substep_timer(profile_substeps)
  z_fixed <- as.numeric(z_fixed)
  theta_mean <- as.numeric(theta_mean)
  theta_cov <- as.matrix(theta_cov)
  if (length(z_fixed) != block$n || length(theta_mean) != block$p || !all(dim(theta_cov) == c(block$p, block$p))) {
    return(NULL)
  }
  beta <- block$beta_index
  alpha <- block$alpha_index
  Xb <- block$X_beta_stack
  Xa <- block$X_alpha_stack
  y_idx <- block$y_index
  g_idx <- block$g_index
  paired_beta <- app_latent_fixed_block_has_paired_beta_rows(block)
  fixed_mean <- numeric(block$n)
  if (isTRUE(paired_beta)) {
    beta_mean <- timer$time("fixed_mean_beta_paired", {
      as.numeric(Xb[y_idx, , drop = FALSE] %*% theta_mean[beta])
    })
    fixed_mean[y_idx] <- beta_mean
    fixed_mean[g_idx] <- beta_mean
  } else {
    fixed_mean <- timer$time("fixed_mean_beta_all", {
      as.numeric(Xb %*% theta_mean[beta])
    })
  }
  if (length(g_idx)) {
    fixed_mean[g_idx] <- fixed_mean[g_idx] + timer$time("fixed_mean_alpha_g", {
      as.numeric(Xa[g_idx, , drop = FALSE] %*% theta_mean[alpha])
    })
  }
  diag_cov <- timer$time("fixed_cov_diagonal_check", {
    app_latent_diagonal_values(theta_cov)
  })
  if (!is.null(diag_cov)) {
    fixed_cov <- numeric(block$n)
    if (isTRUE(paired_beta)) {
      beta_cov <- timer$time("fixed_cov_beta_diag_paired", {
        as.numeric((Xb[y_idx, , drop = FALSE]^2) %*% diag_cov[beta])
      })
      fixed_cov[y_idx] <- beta_cov
      fixed_cov[g_idx] <- beta_cov
    } else {
      fixed_cov <- timer$time("fixed_cov_beta_diag_all", {
        as.numeric((Xb^2) %*% diag_cov[beta])
      })
    }
    if (length(g_idx)) {
      Xa_g <- Xa[g_idx, , drop = FALSE]
      fixed_cov[g_idx] <- fixed_cov[g_idx] + timer$time("fixed_cov_alpha_diag_g", {
        as.numeric((Xa_g^2) %*% diag_cov[alpha])
      })
    }
  } else {
    Sigma_bb <- timer$time("fixed_cov_extract_sigma_bb", theta_cov[beta, beta, drop = FALSE])
    Sigma_ba <- timer$time("fixed_cov_extract_sigma_ba", theta_cov[beta, alpha, drop = FALSE])
    Sigma_aa <- timer$time("fixed_cov_extract_sigma_aa", theta_cov[alpha, alpha, drop = FALSE])
    fixed_cov <- numeric(block$n)
    if (isTRUE(paired_beta)) {
      Xb_y <- Xb[y_idx, , drop = FALSE]
      beta_cov <- timer$time("fixed_cov_beta_dense_paired", {
        rowSums((Xb_y %*% Sigma_bb) * Xb_y)
      })
      fixed_cov[y_idx] <- beta_cov
      fixed_cov[g_idx] <- beta_cov
    } else {
      fixed_cov <- timer$time("fixed_cov_beta_dense_all", {
        rowSums((Xb %*% Sigma_bb) * Xb)
      })
    }
    if (length(g_idx)) {
      Xb_g <- Xb[g_idx, , drop = FALSE]
      Xa_g <- Xa[g_idx, , drop = FALSE]
      fixed_cov[g_idx] <- fixed_cov[g_idx] + timer$time("fixed_cov_beta_alpha_dense_g", {
        2 * rowSums((Xb_g %*% Sigma_ba) * Xa_g)
      }) + timer$time("fixed_cov_alpha_dense_g", {
        rowSums((Xa_g %*% Sigma_aa) * Xa_g)
      })
    }
  }
  fixed_second <- fixed_mean^2 + fixed_cov
  out <- list(
    R = pmax(z_fixed^2 - 2 * z_fixed * fixed_mean + fixed_second, 1.0e-12),
    e = z_fixed - fixed_mean,
    mean = fixed_mean,
    covariance = fixed_cov
  )
  attr(out, "substep_timing") <- timer$collect()
  out
}

app_latent_row_moments_streamed_grouped <- function(design, y_mean, y_cov, theta_mean, theta_cov, profile_substeps = FALSE) {
  timer <- app_latent_substep_timer(profile_substeps)
  future <- timer$time("future_builder", {
    design$future_builder(y_mean)
  })
  H_fixed <- as.matrix(design$H_fixed)
  z_fixed <- as.numeric(design$z_fixed)
  source_fixed <- as.character(design$source_fixed)
  p <- ncol(H_fixed)
  H_y <- as.matrix(future$H_y)
  H_g_key <- app_latent_future_H_g_key(future)
  J_y <- future$J_y
  J_g_key <- app_latent_future_J_g_key(future)
  g_future_index <- app_latent_future_g_index(future)
  z_g <- as.numeric(future$z_g)
  H_future <- length(y_mean)
  if (ncol(H_y) != p || ncol(H_g_key) != p) {
    stop("Future latent-path keyed design has incompatible column count.", call. = FALSE)
  }
  if (nrow(H_y) != H_future || nrow(H_g_key) != H_future) {
    stop("Future latent-path keyed design is not aligned with the future path.", call. = FALSE)
  }
  if (length(J_y) != H_future || length(J_g_key) != H_future) {
    stop("Future latent-path keyed Jacobians are not aligned with the future path.", call. = FALSE)
  }
  if (length(g_future_index) != length(z_g)) {
    stop("GloFAS future index and observation vectors have different lengths.", call. = FALSE)
  }
  if (any(g_future_index < 1L | g_future_index > H_future)) {
    stop("GloFAS future index is outside the available future horizon.", call. = FALSE)
  }

  fixed_block <- timer$time("fixed_block_guard", {
    certificate <- design$fixed_pairing_certificate %||% NULL
    certified_optimized <- isTRUE(certificate$optimization_enabled) &&
      app_latent_pairing_certificate_valid(certificate)
    app_latent_fixed_block_design(
      design = design,
      verify_dense = !isTRUE(certified_optimized)
    )
  })
  fixed_block_moments <- timer$time("fixed_block_moments", {
    app_latent_fixed_row_moments_block(
      fixed_block,
      z_fixed,
      theta_mean,
      theta_cov,
      profile_substeps = profile_substeps
    )
  })
  if (is.null(fixed_block_moments)) {
    dense_fixed <- timer$time("fixed_dense_fallback", {
      fixed_mean <- as.numeric(H_fixed %*% theta_mean)
      fixed_cov <- H_fixed %*% theta_cov
      fixed_second <- fixed_mean^2 + rowSums(fixed_cov * H_fixed)
      list(
        R = pmax(z_fixed^2 - 2 * z_fixed * fixed_mean + fixed_second, 1.0e-12),
        e = z_fixed - fixed_mean
      )
    })
    fixed_R <- dense_fixed$R
    fixed_e <- dense_fixed$e
  } else {
    fixed_R <- fixed_block_moments$R
    fixed_e <- fixed_block_moments$e
  }
  fixed <- list(
    H = H_fixed,
    z = z_fixed,
    source = source_fixed,
    R = fixed_R,
    e = fixed_e,
    n = nrow(H_fixed)
  )
  if (!is.null(fixed_block_moments)) fixed$block <- fixed_block

  R_y <- numeric(H_future)
  e_y <- numeric(H_future)
  b_y <- vector("list", H_future)
  trace_y <- numeric(H_future)
  paired_future_jacobian <- app_latent_future_has_paired_jacobians(future)
  paired_trace_terms <- if (isTRUE(paired_future_jacobian)) {
    timer$time("future_paired_trace_terms", {
      jacobian_trace <- vapply(seq_len(H_future), function(h) {
        app_latent_jacobian_trace_theta(
          J_y[[h]], y_cov, theta_mean, theta_cov
        )
      }, numeric(1L))
      list(
        trace_y = app_latent_quad_theta_rows(
          H_y, theta_mean, theta_cov
        ) + jacobian_trace,
        trace_g = app_latent_quad_theta_rows(
          H_g_key, theta_mean, theta_cov
        ) + jacobian_trace
      )
    })
  } else {
    NULL
  }
  y_loop <- timer$time("future_y_loop", {
    R_y_local <- numeric(H_future)
    e_y_local <- numeric(H_future)
    b_y_local <- vector("list", H_future)
    trace_y_local <- numeric(H_future)
    if (isTRUE(paired_future_jacobian)) {
      trace_y_local <- paired_trace_terms$trace_y
    }
    for (h in seq_len(H_future)) {
      J <- as.matrix(J_y[[h]])
      if (!all(dim(J) == c(p, H_future))) {
        stop("Future Y Jacobian has incompatible dimensions.", call. = FALSE)
      }
      h_vec <- as.numeric(H_y[h, ])
      if (!isTRUE(paired_future_jacobian)) {
        trace_y_local[[h]] <- app_latent_trace_S_theta_parts(
          h_vec, J, y_cov, theta_mean, theta_cov
        )
      }
      b_y_local[[h]] <- h_vec * y_mean[[h]] + as.numeric(J %*% y_cov[, h, drop = FALSE])
      z_second <- y_mean[[h]]^2 + y_cov[h, h]
      R_y_local[[h]] <- max(as.numeric(z_second - 2 * sum(b_y_local[[h]] * theta_mean) + trace_y_local[[h]]), 1.0e-12)
      e_y_local[[h]] <- as.numeric(y_mean[[h]] - sum(h_vec * theta_mean))
    }
    list(R_y = R_y_local, e_y = e_y_local, b_y = b_y_local, trace_y = trace_y_local)
  })
  R_y <- y_loop$R_y
  e_y <- y_loop$e_y
  b_y <- y_loop$b_y
  trace_y <- y_loop$trace_y

  R_g <- numeric(length(z_g))
  e_g <- numeric(length(z_g))
  trace_g <- numeric(H_future)
  u_g <- numeric(H_future)
  g_key_loop <- timer$time("future_g_key_loop", {
    trace_g_local <- numeric(H_future)
    u_g_local <- numeric(H_future)
    if (isTRUE(paired_future_jacobian)) {
      trace_g_local <- paired_trace_terms$trace_g
    }
    for (h in seq_len(H_future)) {
      J <- as.matrix(J_g_key[[h]])
      if (!all(dim(J) == c(p, H_future))) {
        stop("Future GloFAS keyed Jacobian has incompatible dimensions.", call. = FALSE)
      }
      h_vec <- as.numeric(H_g_key[h, ])
      if (!isTRUE(paired_future_jacobian)) {
        trace_g_local[[h]] <- app_latent_trace_S_theta_parts(
          h_vec, J, y_cov, theta_mean, theta_cov
        )
      }
      u_g_local[[h]] <- sum(h_vec * theta_mean)
    }
    list(trace_g = trace_g_local, u_g = u_g_local)
  })
  trace_g <- g_key_loop$trace_g
  u_g <- g_key_loop$u_g
  g_member_loop <- timer$time("future_g_member_loop", {
    R_g_local <- numeric(length(z_g))
    e_g_local <- numeric(length(z_g))
    for (i in seq_along(z_g)) {
      h <- g_future_index[[i]]
      z <- z_g[[i]]
      R_g_local[[i]] <- max(as.numeric(z^2 - 2 * z * u_g[[h]] + trace_g[[h]]), 1.0e-12)
      e_g_local[[i]] <- as.numeric(z - u_g[[h]])
    }
    list(R_g = R_g_local, e_g = e_g_local)
  })
  R_g <- g_member_loop$R_g
  e_g <- g_member_loop$e_g

  future_block <- list(
    X_future = future$X_future,
    X_beta_future = future$X_beta_future %||% future$X_future,
    X_alpha_future = future$X_alpha_future %||% future$X_future,
    H_y = H_y,
    H_g_key = H_g_key,
    J_y = J_y,
    J_g_key = J_g_key,
    g_future_index = g_future_index,
    g_index_by_h = split(seq_along(g_future_index), factor(g_future_index, levels = seq_len(H_future))),
    z_g = z_g,
    paired_future_jacobian = isTRUE(paired_future_jacobian),
    y_mean = as.numeric(y_mean),
    y_second = as.numeric(y_mean)^2 + diag(y_cov),
    y_cov = as.matrix(y_cov),
    b_y = b_y,
    R_y = R_y,
    e_y = e_y,
    R_g = R_g,
    e_g = e_g,
    row_info_y = future$row_info_y,
    row_info_g = future$row_info_g,
    n_y = H_future,
    n_g = length(z_g)
  )
  source <- factor(c(source_fixed, rep("Y", H_future), rep("G", length(z_g))), levels = c("Y", "G"))
  out <- list(
    fixed = fixed,
    future = future_block,
    source = source,
    strategy = "streamed_grouped",
    metadata = list(
      n_future_groups = H_future,
      n_future_rows = H_future + length(z_g),
      n_glofas_future_rows = length(z_g)
    )
  )
  substep_timing <- timer$collect()
  fixed_substeps <- attr(fixed_block_moments, "substep_timing", exact = TRUE)
  if (!is.null(fixed_substeps) && nrow(fixed_substeps)) {
    fixed_substeps$step <- paste0("fixed_block_moments.", fixed_substeps$step)
    substep_timing <- rbind(substep_timing, fixed_substeps)
  }
  attr(out, "substep_timing") <- substep_timing
  out
}

app_latent_row_moments <- function(design, y_mean, y_cov, theta_mean, theta_cov, strategy = "streamed_grouped", profile_substeps = FALSE) {
  strategy <- tolower(as.character(strategy %||% "streamed_grouped"))
  if (identical(strategy, "dense_debug")) {
    return(app_latent_row_moments_dense_debug(design, y_mean, y_cov, theta_mean, theta_cov))
  }
  if (identical(strategy, "streamed_grouped")) {
    return(app_latent_row_moments_streamed_grouped(
      design,
      y_mean,
      y_cov,
      theta_mean,
      theta_cov,
      profile_substeps = profile_substeps
    ))
  }
  stop(sprintf("Unsupported latent-path row-moment strategy '%s'.", strategy), call. = FALSE)
}

app_latent_all_source <- function(row_moments) {
  if (!is.null(row_moments$source)) return(factor(as.character(row_moments$source), levels = c("Y", "G")))
  rows <- row_moments$rows %||% list()
  factor(c(row_moments$fixed$source, vapply(rows, `[[`, character(1L), "source")), levels = c("Y", "G"))
}

app_latent_all_R <- function(row_moments) {
  if (identical(row_moments$strategy, "streamed_grouped")) {
    return(c(row_moments$fixed$R, row_moments$future$R_y, row_moments$future$R_g))
  }
  rows <- row_moments$rows %||% list()
  c(row_moments$fixed$R, vapply(rows, `[[`, numeric(1L), "R"))
}

app_latent_all_e <- function(row_moments) {
  if (identical(row_moments$strategy, "streamed_grouped")) {
    return(c(row_moments$fixed$e, row_moments$future$e_y, row_moments$future$e_g))
  }
  rows <- row_moments$rows %||% list()
  c(row_moments$fixed$e, vapply(rows, `[[`, numeric(1L), "e"))
}

app_latent_fixed_theta_stats_chunks <- function(row_moments, e_inv_v, sigma_state, constants, chunks = NULL) {
  fixed <- row_moments$fixed
  p <- ncol(fixed$H)
  chunks <- app_latent_normalize_source_chunks(fixed$source, chunks)
  precision <- matrix(0, p, p)
  rhs <- numeric(p)
  for (chunk in chunks) {
    idx <- chunk$index
    if (!length(idx)) next
    src <- chunk$source
    H <- fixed$H[idx, , drop = FALSE]
    sig_inv <- sigma_state$inv_mean[[src]]
    w <- as.numeric(sig_inv * e_inv_v[idx] / constants$B)
    precision <- precision + crossprod(H, H * w)
    rhs <- rhs + as.numeric(crossprod(H, sig_inv / constants$B * (e_inv_v[idx] * fixed$z[idx] - constants$A)))
  }
  list(precision = 0.5 * (precision + t(precision)), rhs = rhs)
}

app_latent_fixed_theta_stats_block <- function(row_moments, e_inv_v, sigma_state, constants, profile_substeps = FALSE) {
  fixed <- row_moments$fixed
  block <- app_latent_fixed_block_design(fixed = fixed)
  if (is.null(block)) return(NULL)
  timer <- app_latent_substep_timer(profile_substeps)
  e_inv_v <- as.numeric(e_inv_v)
  if (length(e_inv_v) < block$n || length(fixed$z) != block$n) return(NULL)
  beta <- block$beta_index
  alpha <- block$alpha_index
  y_idx <- block$y_index
  g_idx <- block$g_index
  Xb <- block$X_beta_stack
  Xa <- block$X_alpha_stack
  p <- block$p
  precision <- matrix(0, p, p)
  rhs <- numeric(p)
  paired_beta <- app_latent_fixed_block_has_paired_beta_rows(block)
  sig_y <- if (length(y_idx)) sigma_state$inv_mean[["Y"]] else NA_real_
  sig_g <- if (length(g_idx)) sigma_state$inv_mean[["G"]] else NA_real_
  w_y <- if (length(y_idx)) as.numeric(sig_y * e_inv_v[y_idx] / constants$B) else numeric()
  c_y <- if (length(y_idx)) {
    as.numeric(sig_y / constants$B * (e_inv_v[y_idx] * fixed$z[y_idx] - constants$A))
  } else {
    numeric()
  }
  w_g <- if (length(g_idx)) as.numeric(sig_g * e_inv_v[g_idx] / constants$B) else numeric()
  c_g <- if (length(g_idx)) {
    as.numeric(sig_g / constants$B * (e_inv_v[g_idx] * fixed$z[g_idx] - constants$A))
  } else {
    numeric()
  }
  if (isTRUE(paired_beta)) {
    Xb_y <- Xb[y_idx, , drop = FALSE]
    paired_stats <- timer$time("fixed_theta_paired_beta_fused", {
      list(
        precision = app_latent_weighted_crossprod(Xb_y, w = w_y + w_g),
        rhs = as.numeric(crossprod(Xb_y, c_y + c_g))
      )
    })
    precision[beta, beta] <- precision[beta, beta] + paired_stats$precision
    rhs[beta] <- rhs[beta] + paired_stats$rhs
  }
  if (length(y_idx)) {
    if (!isTRUE(paired_beta)) {
      Xb_y <- Xb[y_idx, , drop = FALSE]
      y_stats <- timer$time("fixed_theta_y_beta", {
        list(
          precision = app_latent_weighted_crossprod(Xb_y, w = w_y),
          rhs = as.numeric(crossprod(Xb_y, c_y))
        )
      })
      precision[beta, beta] <- precision[beta, beta] + y_stats$precision
      rhs[beta] <- rhs[beta] + y_stats$rhs
    }
  }
  if (length(g_idx)) {
    Xb_g <- Xb[g_idx, , drop = FALSE]
    Xa_g <- Xa[g_idx, , drop = FALSE]
    P_bb_g <- if (!isTRUE(paired_beta)) timer$time("fixed_theta_g_beta_beta", {
      app_latent_weighted_crossprod(Xb_g, w = w_g)
    }) else NULL
    P_ba_g <- timer$time("fixed_theta_g_beta_alpha", {
      crossprod(Xb_g, Xa_g * w_g)
    })
    P_aa_g <- timer$time("fixed_theta_g_alpha_alpha", {
      crossprod(Xa_g, Xa_g * w_g)
    })
    if (!is.null(P_bb_g)) precision[beta, beta] <- precision[beta, beta] + P_bb_g
    precision[beta, alpha] <- precision[beta, alpha] + P_ba_g
    precision[alpha, beta] <- precision[alpha, beta] + t(P_ba_g)
    precision[alpha, alpha] <- precision[alpha, alpha] + P_aa_g
    rhs_g <- timer$time("fixed_theta_g_rhs", {
      list(
        beta = if (!isTRUE(paired_beta)) as.numeric(crossprod(Xb_g, c_g)) else numeric(),
        alpha = as.numeric(crossprod(Xa_g, c_g))
      )
    })
    if (!isTRUE(paired_beta)) rhs[beta] <- rhs[beta] + rhs_g$beta
    rhs[alpha] <- rhs[alpha] + rhs_g$alpha
  }
  if (!is.null(block$feature_names) && length(block$feature_names) == p) {
    dimnames(precision) <- list(block$feature_names, block$feature_names)
  }
  out <- list(
    precision = 0.5 * (precision + t(precision)),
    rhs = rhs,
    paired_beta_path = isTRUE(paired_beta)
  )
  attr(out, "substep_timing") <- timer$collect()
  out
}

app_latent_fixed_sigma_stats_chunks <- function(row_moments, e_v, e_inv_v, constants, chunks = NULL) {
  fixed <- row_moments$fixed
  chunks <- app_latent_normalize_source_chunks(fixed$source, chunks)
  shape <- c(Y = 0, G = 0)
  rate <- c(Y = 0, G = 0)
  for (chunk in chunks) {
    idx <- chunk$index
    if (!length(idx)) next
    src <- chunk$source
    shape[[src]] <- shape[[src]] + 1.5 * length(idx)
    quad <- e_inv_v[idx] * fixed$R[idx] - 2 * constants$A * fixed$e[idx] + constants$A^2 * e_v[idx]
    rate[[src]] <- rate[[src]] + sum(e_v[idx] + quad / (2 * constants$B))
  }
  list(shape = shape, rate = rate)
}

app_latent_update_theta <- function(row_moments, e_inv_v, sigma_state, constants, prior_state, chunking = NULL, profile_substeps = FALSE) {
  timer <- app_latent_substep_timer(profile_substeps)
  chunking <- app_latent_normalize_chunking_control(chunking)
  p <- ncol(row_moments$fixed$H)
  precision <- timer$time("theta_prior_precision", {
    diag(prior_state$prior_precision, p)
  })
  rhs <- numeric(p)
  fixed <- row_moments$fixed
  fixed_chunks <- if (isTRUE(chunking$enabled)) app_latent_make_source_row_chunks(fixed$source, chunking$chunk_size) else NULL
  fixed_stats <- timer$time("theta_fixed_stats", {
    app_latent_fixed_theta_stats_block(
      row_moments,
      e_inv_v,
      sigma_state,
      constants,
      profile_substeps = profile_substeps
    )
  })
  if (is.null(fixed_stats)) {
    fixed_stats <- timer$time("theta_fixed_dense_fallback", {
      app_latent_fixed_theta_stats_chunks(
      row_moments = row_moments,
      e_inv_v = e_inv_v,
      sigma_state = sigma_state,
      constants = constants,
      chunks = fixed_chunks
      )
    })
  }
  precision <- precision + fixed_stats$precision
  rhs <- rhs + fixed_stats$rhs
  if (identical(row_moments$strategy, "streamed_grouped")) {
    future <- row_moments$future
    n_y <- as.integer(future$n_y)
    offset <- fixed$n
    sig_y <- sigma_state$inv_mean[["Y"]]
    sig_g <- sigma_state$inv_mean[["G"]]
    g_index_by_h <- future$g_index_by_h %||%
      split(seq_along(future$g_future_index), factor(future$g_future_index, levels = seq_len(n_y)))
    if (isTRUE(future$paired_future_jacobian)) {
      future_paired_stats <- timer$time("theta_future_paired_jacobian", {
        e_y <- e_inv_v[offset + seq_len(n_y)]
        coeff_y <- sig_y * e_y / constants$B
        coeff_g <- numeric(n_y)
        rhs_weight_g <- numeric(n_y)
        for (h in seq_len(n_y)) {
          idx <- as.integer(g_index_by_h[[h]] %||% integer(0))
          if (!length(idx)) next
          global_idx <- offset + n_y + idx
          einv <- e_inv_v[global_idx]
          coeff_g[[h]] <- sig_g * sum(einv) / constants$B
          rhs_weight_g[[h]] <- sig_g / constants$B * (
            sum(einv * future$z_g[idx]) - constants$A * length(idx)
          )
        }
        precision_future <- app_latent_weighted_crossprod(
          future$H_y,
          w = coeff_y
        ) + app_latent_weighted_crossprod(
          future$H_g_key,
          w = coeff_g
        )
        for (h in seq_len(n_y)) {
          precision_future <- app_latent_add_J_precision(
            precision_future,
            coeff_y[[h]] + coeff_g[[h]],
            future$J_y[[h]],
            future$y_cov
          )
        }
        b_y <- do.call(cbind, future$b_y)
        rhs_y <- as.numeric(b_y %*% (sig_y * e_y / constants$B)) -
          sig_y * constants$A / constants$B * colSums(future$H_y)
        rhs_g <- as.numeric(crossprod(future$H_g_key, rhs_weight_g))
        list(precision = precision_future, rhs = rhs_y + rhs_g)
      })
      precision <- precision + future_paired_stats$precision
      rhs <- rhs + future_paired_stats$rhs
    } else {
      future_y_stats <- timer$time("theta_future_y", {
        precision_y <- matrix(0, p, p)
        rhs_y <- numeric(p)
        for (h in seq_len(n_y)) {
          i <- offset + h
          h_vec <- as.numeric(future$H_y[h, ])
          J <- as.matrix(future$J_y[[h]])
          c_i <- sig_y * e_inv_v[[i]] / constants$B
          precision_y <- app_latent_add_S_precision(precision_y, c_i, h_vec, J, future$y_cov)
          rhs_y <- rhs_y + sig_y / constants$B * (e_inv_v[[i]] * future$b_y[[h]] - constants$A * h_vec)
        }
        list(precision = precision_y, rhs = rhs_y)
      })
      precision <- precision + future_y_stats$precision
      rhs <- rhs + future_y_stats$rhs
      future_g_stats <- timer$time("theta_future_g", {
        precision_g <- matrix(0, p, p)
        rhs_g <- numeric(p)
        for (h in seq_len(n_y)) {
          idx <- as.integer(g_index_by_h[[h]] %||% integer(0))
          if (!length(idx)) next
          global_idx <- offset + n_y + idx
          einv <- e_inv_v[global_idx]
          z <- future$z_g[idx]
          h_vec <- as.numeric(future$H_g_key[h, ])
          J <- as.matrix(future$J_g_key[[h]])
          precision_g <- app_latent_add_S_precision(
            precision_g,
            sig_g * sum(einv) / constants$B,
            h_vec,
            J,
            future$y_cov
          )
          rhs_g <- rhs_g + sig_g / constants$B * (
            h_vec * sum(einv * z) - constants$A * length(idx) * h_vec
          )
        }
        list(precision = precision_g, rhs = rhs_g)
      })
      precision <- precision + future_g_stats$precision
      rhs <- rhs + future_g_stats$rhs
    }
    update <- timer$time("theta_solve_spd", {
      app_latent_solve_spd(precision, rhs)
    })
    substep_timing <- timer$collect()
    fixed_substeps <- attr(fixed_stats, "substep_timing", exact = TRUE)
    if (!is.null(fixed_substeps) && nrow(fixed_substeps)) {
      fixed_substeps$step <- paste0("theta_fixed_stats.", fixed_substeps$step)
      substep_timing <- rbind(substep_timing, fixed_substeps)
    }
    attr(update, "substep_timing") <- substep_timing
    return(update)
  }
  offset <- fixed$n
  dense_future_stats <- timer$time("theta_future_dense_rows", {
    precision_rows <- matrix(0, p, p)
    rhs_rows <- numeric(p)
    for (j in seq_along(row_moments$rows)) {
      i <- offset + j
      row <- row_moments$rows[[j]]
      sig_inv <- sigma_state$inv_mean[[row$source]]
      c_i <- sig_inv * e_inv_v[[i]] / constants$B
      precision_rows <- precision_rows + c_i * row$S
      rhs_rows <- rhs_rows + sig_inv / constants$B * (e_inv_v[[i]] * row$b - constants$A * row$h_mean)
    }
    list(precision = precision_rows, rhs = rhs_rows)
  })
  precision <- precision + dense_future_stats$precision
  rhs <- rhs + dense_future_stats$rhs
  update <- timer$time("theta_solve_spd", {
    app_latent_solve_spd(precision, rhs)
  })
  attr(update, "substep_timing") <- timer$collect()
  update
}

app_latent_update_v <- function(row_moments, sigma_state, constants) {
  source <- app_latent_all_source(row_moments)
  R <- app_latent_all_R(row_moments)
  n_total <- length(R)
  chi <- numeric(n_total)
  psi <- numeric(n_total)
  for (src in c("Y", "G")) {
    idx <- which(source == src)
    if (!length(idx)) next
    sig_inv <- sigma_state$inv_mean[[src]]
    chi[idx] <- sig_inv * R[idx] / constants$B
    psi[idx] <- sig_inv * (constants$A^2 / constants$B + 2)
  }
  app_latent_gig_half_moments(chi, psi)
}

app_latent_update_sigma <- function(row_moments, e_v, e_inv_v, constants, prior_sigma, chunking = NULL) {
  chunking <- app_latent_normalize_chunking_control(chunking)
  a0 <- as.numeric(prior_sigma$a %||% 2)
  b0 <- as.numeric(prior_sigma$b %||% 1)
  shape <- c(Y = a0, G = a0)
  rate <- c(Y = b0, G = b0)
  source <- app_latent_all_source(row_moments)
  R <- app_latent_all_R(row_moments)
  e <- app_latent_all_e(row_moments)
  fixed_n <- as.integer(row_moments$fixed$n %||% 0L)
  if (isTRUE(chunking$enabled) && fixed_n > 0L) {
    fixed_chunks <- app_latent_make_source_row_chunks(row_moments$fixed$source, chunking$chunk_size)
    fixed_stats <- app_latent_fixed_sigma_stats_chunks(
      row_moments = row_moments,
      e_v = e_v,
      e_inv_v = e_inv_v,
      constants = constants,
      chunks = fixed_chunks
    )
    shape <- shape + fixed_stats$shape
    rate <- rate + fixed_stats$rate
    row_idx <- if (fixed_n < length(source)) seq.int(fixed_n + 1L, length(source)) else integer(0)
  } else {
    row_idx <- seq_along(source)
  }
  for (src in c("Y", "G")) {
    idx <- row_idx[source[row_idx] == src]
    if (!length(idx)) next
    shape[[src]] <- shape[[src]] + 1.5 * length(idx)
    quad <- e_inv_v[idx] * R[idx] - 2 * constants$A * e[idx] + constants$A^2 * e_v[idx]
    rate[[src]] <- rate[[src]] + sum(e_v[idx] + quad / (2 * constants$B))
  }
  app_latent_ig_expectations(shape, pmax(rate, 1.0e-12))
}

app_latent_future_objective <- function(y_future, design, theta_mean, theta_cov, e_inv_v, sigma_state, constants, strategy = "grouped") {
  y_future <- as.numeric(y_future)
  future <- design$future_builder(y_future)
  value <- 0
  row_offset <- nrow(design$H_fixed)
  strategy <- tolower(as.character(strategy %||% "grouped"))
  if (identical(strategy, "grouped")) {
    H_y <- as.matrix(future$H_y)
    H_g_key <- app_latent_future_H_g_key(future)
    g_future_index <- app_latent_future_g_index(future)
    g_index_by_h <- split(seq_along(g_future_index), factor(g_future_index, levels = seq_len(nrow(H_g_key))))
    z_g <- as.numeric(future$z_g)
    for (h in seq_len(nrow(H_y))) {
      h_vec <- as.numeric(H_y[h, ])
      z <- y_future[[h]]
      u <- sum(h_vec * theta_mean)
      s <- app_latent_quad_theta(h_vec, theta_mean, theta_cov)
      R <- z^2 - 2 * z * u + s
      sig_inv <- sigma_state$inv_mean[["Y"]]
      i <- row_offset + h
      value <- value -
        sig_inv * e_inv_v[[i]] * R / (2 * constants$B) +
        sig_inv * constants$A * (z - u) / constants$B
    }
    g_offset <- row_offset + nrow(H_y)
    sig_inv <- sigma_state$inv_mean[["G"]]
    for (h in seq_len(nrow(H_g_key))) {
      idx <- as.integer(g_index_by_h[[h]] %||% integer(0))
      if (!length(idx)) next
      h_vec <- as.numeric(H_g_key[h, ])
      u <- sum(h_vec * theta_mean)
      s <- app_latent_quad_theta(h_vec, theta_mean, theta_cov)
      global_idx <- g_offset + idx
      einv <- e_inv_v[global_idx]
      z <- z_g[idx]
      value <- value -
        sig_inv * (sum(einv * z^2) - 2 * u * sum(einv * z) + s * sum(einv)) / (2 * constants$B) +
        sig_inv * constants$A * (sum(z) - length(idx) * u) / constants$B
    }
    return(value)
  }
  if (!identical(strategy, "ungrouped_debug")) {
    stop(sprintf("Unsupported latent future objective strategy '%s'.", strategy), call. = FALSE)
  }

  add_contrib <- function(z, h, source, row_index) {
    e <- z - sum(h * theta_mean)
    R <- z^2 - 2 * z * sum(h * theta_mean) + app_latent_quad_theta(h, theta_mean, theta_cov)
    sig_inv <- sigma_state$inv_mean[[source]]
    value <<- value -
      sig_inv * e_inv_v[[row_index]] * R / (2 * constants$B) +
      sig_inv * constants$A * e / constants$B
  }

  for (h in seq_len(nrow(future$H_y))) {
    add_contrib(y_future[[h]], future$H_y[h, ], "Y", row_offset + h)
  }
  g_offset <- row_offset + nrow(future$H_y)
  H_g <- app_latent_future_H_g_expanded(future)
  for (i in seq_len(nrow(H_g))) {
    add_contrib(future$z_g[[i]], H_g[i, ], "G", g_offset + i)
  }
  value
}

app_latent_update_future_gaussian <- function(y_start, design, theta_mean, theta_cov, e_inv_v, sigma_state, constants, objective_strategy = "grouped") {
  if (identical(objective_strategy, "linearized_delta")) {
    stop("Use app_latent_update_future_gaussian_delta() for the linearized Delta future update.", call. = FALSE)
  }
  fn <- function(y) -app_latent_future_objective(
    y, design, theta_mean, theta_cov, e_inv_v, sigma_state, constants,
    strategy = objective_strategy
  )
  opt <- stats::optim(
    par = as.numeric(y_start),
    fn = fn,
    method = "BFGS",
    control = list(maxit = 100, reltol = 1.0e-8)
  )
  H <- tryCatch(stats::optimHess(opt$par, fn), error = function(e) diag(length(opt$par)))
  eig <- eigen((H + t(H)) / 2, symmetric = TRUE)
  vals <- pmax(eig$values, 1.0e-6)
  cov <- eig$vectors %*% (t(eig$vectors) / vals)
  list(
    mean = as.numeric(opt$par),
    cov = (cov + t(cov)) / 2,
    objective = -opt$value,
    convergence = opt$convergence,
    message = opt$message %||% ""
  )
}

app_latent_update_future_gaussian_delta <- function(row_moments, y_start, theta_mean, theta_cov, e_inv_v, sigma_state, constants, jitter = 1.0e-8) {
  if (!identical(row_moments$strategy, "streamed_grouped")) {
    stop("The linearized Delta future update requires streamed grouped row moments.", call. = FALSE)
  }
  future <- row_moments$future
  H <- as.integer(future$n_y)
  if (!H) stop("The latent future update requires at least one future date.", call. = FALSE)
  precision <- diag(as.numeric(jitter), H)
  rhs <- numeric(H)
  theta_cov <- as.matrix(theta_cov)
  theta_mean <- as.numeric(theta_mean)
  offset <- row_moments$fixed$n

  add_linearized_row <- function(h_vec, J, z0, a, sig_inv, einv, source_count = 1) {
    h_vec <- as.numeric(h_vec)
    J <- as.matrix(J)
    a <- as.numeric(a)
    h_mean <- sum(h_vec * theta_mean)
    lbar <- a - as.numeric(crossprod(J, theta_mean))
    cov_term <- as.numeric(crossprod(J, theta_cov %*% h_vec))
    e0 <- as.numeric(z0 - h_mean)
    Q <- crossprod(J, theta_cov %*% J) + tcrossprod(lbar)
    g <- lbar * e0 + cov_term
    list(
      precision = sig_inv * einv / constants$B * Q,
      rhs = -sig_inv * einv / constants$B * g +
        sig_inv * constants$A / constants$B * source_count * lbar
    )
  }

  sig_y <- sigma_state$inv_mean[["Y"]]
  for (h in seq_len(H)) {
    a <- numeric(H)
    a[[h]] <- 1
    row <- add_linearized_row(
      h_vec = future$H_y[h, ],
      J = future$J_y[[h]],
      z0 = y_start[[h]],
      a = a,
      sig_inv = sig_y,
      einv = e_inv_v[[offset + h]],
      source_count = 1
    )
    precision <- precision + row$precision
    rhs <- rhs + row$rhs
  }

  sig_g <- sigma_state$inv_mean[["G"]]
  zero_a <- numeric(H)
  g_index_by_h <- future$g_index_by_h %||%
    split(seq_along(future$g_future_index), factor(future$g_future_index, levels = seq_len(H)))
  for (h in seq_len(H)) {
    idx <- as.integer(g_index_by_h[[h]] %||% integer(0))
    if (!length(idx)) next
    h_vec <- as.numeric(future$H_g_key[h, ])
    J <- as.matrix(future$J_g_key[[h]])
    h_mean <- sum(h_vec * theta_mean)
    lbar <- zero_a - as.numeric(crossprod(J, theta_mean))
    cov_term <- as.numeric(crossprod(J, theta_cov %*% h_vec))
    Q <- crossprod(J, theta_cov %*% J) + tcrossprod(lbar)
    global_idx <- offset + H + idx
    einv <- e_inv_v[global_idx]
    z <- future$z_g[idx]
    sum_einv <- sum(einv)
    sum_g <- lbar * (sum(einv * z) - h_mean * sum_einv) + cov_term * sum_einv
    precision <- precision + sig_g * sum_einv / constants$B * Q
    rhs <- rhs - sig_g / constants$B * sum_g +
      sig_g * constants$A / constants$B * length(idx) * lbar
  }

  update <- app_latent_solve_spd(precision, rhs, jitter = jitter)
  mean <- as.numeric(y_start) + as.numeric(update$mean)
  cov <- (update$cov + t(update$cov)) / 2
  list(
    mean = mean,
    cov = cov,
    objective = NA_real_,
    convergence = 0L,
    message = "linearized_delta_update",
    precision = update$precision,
    repaired = isTRUE(update$repaired)
  )
}

app_latent_extract_future_linearization <- function(row_moments, design) {
  if (!identical(row_moments$strategy, "streamed_grouped")) return(NULL)
  p_beta <- length(design$beta_index)
  p_alpha <- length(design$alpha_index)
  if (!p_beta || !p_alpha || is.null(row_moments$future$X_future)) return(NULL)
  J_beta <- lapply(row_moments$future$J_y, function(J) {
    as.matrix(J)[design$beta_index, , drop = FALSE]
  })
  J_alpha <- lapply(row_moments$future$J_g_key, function(J) {
    as.matrix(J)[design$alpha_index, , drop = FALSE]
  })
  list(
    strategy = "first_order_delta",
    y_mean = as.numeric(row_moments$future$y_mean),
    X_future = as.matrix(row_moments$future$X_future),
    X_beta_future = as.matrix(row_moments$future$X_beta_future %||% row_moments$future$X_future),
    X_alpha_future = as.matrix(row_moments$future$X_alpha_future %||% row_moments$future$X_future),
    J_x = J_beta,
    J_beta = J_beta,
    J_alpha = J_alpha
  )
}

app_latent_approx_objective <- function(row_moments, e_v, e_inv_v, sigma_state, constants, theta_mean, theta_cov, prior_state) {
  val <- 0
  source <- app_latent_all_source(row_moments)
  R <- app_latent_all_R(row_moments)
  e <- app_latent_all_e(row_moments)
  for (src in c("Y", "G")) {
    idx <- which(source == src)
    if (!length(idx)) next
    sig_inv <- sigma_state$inv_mean[[src]]
    val <- val +
      sum(
        -0.5 * sigma_state$log_mean[[src]] -
          sig_inv * e_v[idx] -
          sig_inv * (e_inv_v[idx] * R[idx] - 2 * constants$A * e[idx] + constants$A^2 * e_v[idx]) / (2 * constants$B)
      )
  }
  e_theta2 <- theta_mean^2 + diag(theta_cov)
  val - 0.5 * sum(prior_state$prior_precision * e_theta2)
}

app_latent_path_warm_start_config <- function(vb_args = list()) {
  cfg <- vb_args$warm_start %||% list(enabled = FALSE)
  if (is.logical(cfg) && length(cfg) == 1L) cfg <- list(enabled = cfg)
  if (!is.list(cfg)) cfg <- list(enabled = app_as_bool(cfg))
  list(
    enabled = app_as_bool(cfg$enabled %||% FALSE),
    fit_object = cfg$fit_object %||% cfg$fit_path %||% cfg$path %||% NULL,
    use_theta = app_as_bool(cfg$use_theta %||% TRUE),
    use_future = app_as_bool(cfg$use_future %||% TRUE),
    use_sigma = app_as_bool(cfg$use_sigma %||% TRUE),
    require_theta = app_as_bool(cfg$require_theta %||% TRUE),
    require_future = app_as_bool(cfg$require_future %||% TRUE),
    require_sigma = app_as_bool(cfg$require_sigma %||% FALSE),
    covariance_jitter = as.numeric(cfg$covariance_jitter %||% 1.0e-8),
    require_contract = app_as_bool(cfg$require_contract %||% FALSE),
    compatibility_mode = match.arg(
      as.character(cfg$compatibility_mode %||% "exact_design"),
      c("exact_design", "coordinate_transfer", "state_only")
    ),
    source_contract = cfg$source_contract %||% cfg$contract %||% NULL
  )
}

app_latent_path_contract_hash <- function(x, prefix = "latent_path_contract_") {
  if (exists("app_qdesn_hash_object", mode = "function")) {
    return(app_qdesn_hash_object(x, prefix = prefix))
  }
  path <- tempfile(prefix, fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(x, path, version = 2L)
  app_sha256_file(path)
}

app_latent_path_warm_start_contract <- function(design, design_hash = NULL) {
  theta_names <- colnames(design$H_fixed)
  if (is.null(theta_names) || any(!nzchar(theta_names))) {
    theta_names <- paste0("theta_", seq_len(ncol(design$H_fixed)))
  }
  future_key <- design$future_key[, intersect(c("target_date", "horizon"), names(design$future_key)), drop = FALSE]
  if ("target_date" %in% names(future_key)) future_key$target_date <- as.character(as.Date(future_key$target_date))
  if ("horizon" %in% names(future_key)) future_key$horizon <- as.integer(future_key$horizon)
  rownames(future_key) <- NULL
  design_hash <- design_hash %||% design$warm_start_design_hash %||% NULL
  if (is.null(design_hash) && exists("app_hash_latent_path_design", mode = "function")) {
    design_hash <- app_hash_latent_path_design(design)
  }
  list(
    version = "1.0",
    design_hash = as.character(design_hash %||% NA_character_),
    quantile_level = as.numeric(design$p0 %||% NA_real_),
    n_theta = ncol(design$H_fixed),
    theta_names = as.character(theta_names),
    theta_names_hash = app_latent_path_contract_hash(as.character(theta_names), "theta_names_"),
    n_future = nrow(design$future_key),
    future_key_hash = app_latent_path_contract_hash(future_key, "future_key_")
  )
}

app_latent_path_read_warm_start_contract <- function(x) {
  if (is.null(x) || !length(x)) return(NULL)
  if (is.list(x)) return(x)
  path <- app_resolve_path(as.character(x[[1L]]), must_work = TRUE)
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("yaml", "yml")) return(app_read_yaml(path))
  if (ext == "rds") return(readRDS(path))
  if (ext == "json") {
    app_require_namespace("jsonlite")
    return(jsonlite::read_json(path, simplifyVector = TRUE))
  }
  stop("Warm-start contract paths must be YAML, JSON, or RDS.", call. = FALSE)
}

app_latent_path_warm_start_compatibility <- function(source, target, mode = "exact_design") {
  mode <- match.arg(mode, c("exact_design", "coordinate_transfer", "state_only"))
  required <- c("design_hash", "quantile_level", "n_theta", "theta_names_hash", "n_future", "future_key_hash")
  missing_source <- setdiff(required, names(source %||% list()))
  missing_target <- setdiff(required, names(target %||% list()))
  if (length(missing_source) || length(missing_target)) {
    return(list(
      accepted = FALSE,
      class = "invalid_contract",
      theta_allowed = FALSE,
      future_allowed = FALSE,
      sigma_allowed = FALSE,
      message = sprintf(
        "warm-start contract is incomplete (source: %s; target: %s)",
        paste(missing_source, collapse = ","),
        paste(missing_target, collapse = ",")
      )
    ))
  }
  same_quantile <- isTRUE(all.equal(
    as.numeric(source$quantile_level),
    as.numeric(target$quantile_level),
    tolerance = 1.0e-12
  ))
  same_theta <- identical(as.integer(source$n_theta), as.integer(target$n_theta)) &&
    identical(as.character(source$theta_names_hash), as.character(target$theta_names_hash))
  same_future <- identical(as.integer(source$n_future), as.integer(target$n_future)) &&
    identical(as.character(source$future_key_hash), as.character(target$future_key_hash))
  source_hash <- as.character(source$design_hash %||% NA_character_)
  target_hash <- as.character(target$design_hash %||% NA_character_)
  same_design <- !is.na(source_hash) && !is.na(target_hash) &&
    nzchar(source_hash) && nzchar(target_hash) && identical(source_hash, target_hash)

  if (same_quantile && same_theta && same_future && same_design) {
    return(list(
      accepted = TRUE,
      class = "exact_design",
      theta_allowed = TRUE,
      future_allowed = TRUE,
      sigma_allowed = TRUE,
      message = "exact semantic design contract matched"
    ))
  }
  if (identical(mode, "coordinate_transfer") && same_quantile && same_theta && same_future) {
    return(list(
      accepted = TRUE,
      class = "coordinate_transfer",
      theta_allowed = TRUE,
      future_allowed = TRUE,
      sigma_allowed = TRUE,
      message = "feature coordinates and future key matched; design values differ"
    ))
  }
  if (identical(mode, "state_only") && same_quantile && same_future) {
    return(list(
      accepted = TRUE,
      class = "state_only",
      theta_allowed = FALSE,
      future_allowed = TRUE,
      sigma_allowed = TRUE,
      message = "only future-path and source-scale state transfer is allowed"
    ))
  }
  list(
    accepted = FALSE,
    class = "incompatible",
    theta_allowed = FALSE,
    future_allowed = FALSE,
    sigma_allowed = FALSE,
    message = sprintf(
      "warm-start contract rejected: mode=%s same_quantile=%s same_theta=%s same_future=%s same_design=%s",
      mode, same_quantile, same_theta, same_future, same_design
    )
  )
}

app_latent_path_warm_start_fit <- function(path) {
  resolved <- app_resolve_path(path, must_work = TRUE)
  obj <- readRDS(resolved)
  fit <- obj$fit %||% obj
  if (!is.list(fit) || is.null(fit$summary)) {
    stop(sprintf("Warm-start object is not a latent-path fit with a summary: %s", resolved), call. = FALSE)
  }
  list(
    fit = fit,
    path = app_prefer_repo_relative_path(resolved),
    sha256 = app_sha256_file(resolved)
  )
}

app_latent_path_warm_start_contract_from_fit <- function(path) {
  source <- app_latent_path_warm_start_fit(path)
  source$fit$warm_start_contract %||%
    source$fit$summary$warm_start_contract %||%
    NULL
}

app_latent_path_warm_start_cov <- function(x, dim, jitter = 1.0e-8, label = "covariance") {
  if (is.null(x)) return(NULL)
  x <- as.matrix(x)
  if (!identical(dim(x), c(as.integer(dim), as.integer(dim)))) {
    stop(sprintf("Warm-start %s has dimension %s but expected %d x %d.", label, paste(dim(x), collapse = " x "), dim, dim), call. = FALSE)
  }
  if (any(!is.finite(x))) {
    stop(sprintf("Warm-start %s contains non-finite entries.", label), call. = FALSE)
  }
  x <- (x + t(x)) / 2
  eig <- eigen(x, symmetric = TRUE)
  floor_val <- max(as.numeric(jitter), .Machine$double.eps)
  vals <- pmax(as.numeric(eig$values), floor_val)
  out <- eig$vectors %*% (t(eig$vectors) * vals)
  out <- (out + t(out)) / 2
  dimnames(out) <- dimnames(x)
  out
}

app_latent_path_warm_start_sigma <- function(fit) {
  sigma <- fit$variational_state$sigma %||% NULL
  if (is.null(sigma)) sigma <- fit$summary$sigma_state %||% NULL
  if (is.null(sigma)) return(NULL)
  if (!all(c("shape", "rate") %in% names(sigma))) return(NULL)
  shape <- sigma$shape
  rate <- sigma$rate
  if (is.null(names(shape))) names(shape) <- c("Y", "G")[seq_along(shape)]
  if (is.null(names(rate))) names(rate) <- c("Y", "G")[seq_along(rate)]
  if (!all(c("Y", "G") %in% names(shape)) || !all(c("Y", "G") %in% names(rate))) return(NULL)
  app_latent_ig_expectations(shape[c("Y", "G")], rate[c("Y", "G")])
}

app_latent_path_warm_start_prepare <- function(design, vb_args = list(), p, H_future) {
  cfg <- app_latent_path_warm_start_config(vb_args)
  diagnostics <- list(
    enabled = cfg$enabled,
    used = FALSE,
    theta_used = FALSE,
    future_used = FALSE,
    sigma_used = FALSE,
    source_path = NA_character_,
    source_sha256 = NA_character_,
    contract_required = cfg$require_contract,
    compatibility_mode = cfg$compatibility_mode,
    compatibility_class = if (isTRUE(cfg$require_contract)) NA_character_ else "legacy_dimension_only",
    compatibility_message = NA_character_,
    message = if (isTRUE(cfg$enabled)) NA_character_ else "warm start disabled"
  )
  out <- list(
    theta_mean = NULL,
    theta_cov = NULL,
    y_mean = NULL,
    y_cov = NULL,
    sigma_state = NULL,
    diagnostics = diagnostics
  )
  if (!isTRUE(cfg$enabled)) return(out)
  if (is.null(cfg$fit_object) || !nzchar(as.character(cfg$fit_object[[1L]]))) {
    stop("Warm start is enabled but no fit_object/path was supplied.", call. = FALSE)
  }

  source <- app_latent_path_warm_start_fit(cfg$fit_object)
  fit <- source$fit
  messages <- character()
  out$diagnostics$source_path <- source$path
  out$diagnostics$source_sha256 <- source$sha256

  source_contract <- app_latent_path_read_warm_start_contract(
    cfg$source_contract %||% fit$warm_start_contract %||% fit$summary$warm_start_contract %||% NULL
  )
  compatibility <- NULL
  if (isTRUE(cfg$require_contract) || !is.null(source_contract)) {
    if (is.null(source_contract)) {
      stop("Strict warm start requires a source semantic contract.", call. = FALSE)
    }
    target_contract <- app_latent_path_warm_start_contract(design)
    compatibility <- app_latent_path_warm_start_compatibility(
      source_contract,
      target_contract,
      mode = cfg$compatibility_mode
    )
    out$diagnostics$compatibility_class <- compatibility$class
    out$diagnostics$compatibility_message <- compatibility$message
    if (!isTRUE(compatibility$accepted)) stop(compatibility$message, call. = FALSE)
  }

  theta_allowed <- is.null(compatibility) || isTRUE(compatibility$theta_allowed)
  future_allowed <- is.null(compatibility) || isTRUE(compatibility$future_allowed)
  sigma_allowed <- is.null(compatibility) || isTRUE(compatibility$sigma_allowed)

  if (isTRUE(cfg$use_theta) && isTRUE(theta_allowed)) {
    theta_mean <- fit$variational_state$theta_mean %||% fit$summary$theta_mean %||% NULL
    theta_cov <- fit$variational_state$theta_cov %||% fit$summary$theta_cov %||% NULL
    ok <- !is.null(theta_mean) && length(theta_mean) == p && !is.null(theta_cov)
    if (!ok) {
      msg <- sprintf("theta warm start unavailable or dimension-mismatched; expected length %d.", p)
      if (isTRUE(cfg$require_theta)) stop(msg, call. = FALSE)
      messages <- c(messages, msg)
    } else {
      out$theta_mean <- as.numeric(theta_mean)
      names(out$theta_mean) <- colnames(design$H_fixed) %||% names(theta_mean)
      out$theta_cov <- app_latent_path_warm_start_cov(theta_cov, p, cfg$covariance_jitter, "theta_cov")
      out$diagnostics$theta_used <- TRUE
    }
  } else if (isTRUE(cfg$use_theta) && !isTRUE(theta_allowed)) {
    messages <- c(messages, "theta transfer disabled by semantic compatibility policy")
  }

  if (isTRUE(cfg$use_future) && isTRUE(future_allowed)) {
    y_mean <- fit$variational_state$y_future_mean %||% fit$summary$y_future_mean %||% NULL
    y_cov <- fit$variational_state$y_future_cov %||% fit$summary$y_future_cov %||% NULL
    ok <- !is.null(y_mean) && length(y_mean) == H_future && !is.null(y_cov)
    if (!ok) {
      msg <- sprintf("future-path warm start unavailable or dimension-mismatched; expected length %d.", H_future)
      if (isTRUE(cfg$require_future)) stop(msg, call. = FALSE)
      messages <- c(messages, msg)
    } else {
      out$y_mean <- as.numeric(y_mean)
      out$y_cov <- app_latent_path_warm_start_cov(y_cov, H_future, cfg$covariance_jitter, "y_future_cov")
      out$diagnostics$future_used <- TRUE
    }
  } else if (isTRUE(cfg$use_future) && !isTRUE(future_allowed)) {
    messages <- c(messages, "future-path transfer disabled by semantic compatibility policy")
  }

  if (isTRUE(cfg$use_sigma) && isTRUE(sigma_allowed)) {
    sigma_state <- app_latent_path_warm_start_sigma(fit)
    if (is.null(sigma_state)) {
      msg <- "sigma warm start unavailable; using default sigma initialization."
      if (isTRUE(cfg$require_sigma)) stop(msg, call. = FALSE)
      messages <- c(messages, msg)
    } else {
      out$sigma_state <- sigma_state
      out$diagnostics$sigma_used <- TRUE
    }
  } else if (isTRUE(cfg$use_sigma) && !isTRUE(sigma_allowed)) {
    messages <- c(messages, "source-scale transfer disabled by semantic compatibility policy")
  }

  out$diagnostics$used <- isTRUE(out$diagnostics$theta_used) ||
    isTRUE(out$diagnostics$future_used) ||
    isTRUE(out$diagnostics$sigma_used)
  if (!length(messages)) {
    messages <- if (isTRUE(out$diagnostics$used)) "warm start accepted" else "warm start enabled but no block was used"
  }
  out$diagnostics$message <- paste(messages, collapse = " | ")
  out
}

app_fit_latent_path_al_vb_core <- function(design, p0, coefficient_prior = "rhs_ns", vb_args = list(), seed = NULL) {
  if (!identical(tolower(as.character(vb_args$likelihood_family %||% "al")), "al")) {
    stop("The article-side latent-path VB fitter currently supports AL likelihood only.", call. = FALSE)
  }
  p <- ncol(design$H_fixed)
  H_future <- nrow(design$future_key)
  if (!H_future) stop("Latent-path design has no future horizon.", call. = FALSE)
  fixed_pairing_certificate <- design$fixed_pairing_certificate %||% NULL
  if (isTRUE(fixed_pairing_certificate$optimization_enabled) &&
      isTRUE(fixed_pairing_certificate$paired_beta_rows)) {
    fixed_pairing_block <- app_latent_fixed_block_design(
      design = design,
      verify_dense = FALSE
    )
    if (is.null(fixed_pairing_block) ||
        !app_latent_pairing_certificate_matches_block(
          fixed_pairing_certificate,
          fixed_pairing_block
        )) {
      stop(
        "Latent-path fixed-row pairing certificate does not match the design.",
        call. = FALSE
      )
    }
  }

  constants <- app_latent_al_constants(p0)
  seed <- as.integer(seed %||% vb_args$seed %||% 20260513L)
  max_iter <- as.integer(vb_args$max_iter %||% 200L)
  min_iter <- as.integer(vb_args$min_iter_elbo %||% 5L)
  tol <- as.numeric(vb_args$tol %||% 1.0e-4)
  n_draws <- as.integer(vb_args$n_draws %||% 500L)
  diagnostics_args <- vb_args$diagnostics %||% list()
  fixed_iterations <- isTRUE(diagnostics_args$fixed_iterations %||% FALSE)
  stop_after_iteration <- suppressWarnings(as.integer(
    diagnostics_args$stop_after_iteration %||% NA_integer_
  ))
  if (!is.finite(max_iter) || max_iter < 1L) max_iter <- 200L
  if (!is.finite(n_draws) || n_draws < 1L) n_draws <- 500L
  if (is.finite(stop_after_iteration) &&
      (stop_after_iteration < 1L || stop_after_iteration > max_iter)) {
    stop("diagnostics.stop_after_iteration must be between 1 and max_iter.", call. = FALSE)
  }
  rhs_control <- app_latent_normalize_rhs_control(vb_args$rhs %||% list())
  rhs_active <- tolower(as.character(coefficient_prior %||% "rhs_ns")) %in% c("rhs", "rhs_ns")
  minimum_rhs_convergence_iter <- if (rhs_active) {
    app_latent_rhs_minimum_convergence_iteration(rhs_control)
  } else {
    1L
  }
  if (max_iter < minimum_rhs_convergence_iter && !isTRUE(fixed_iterations)) {
    stop(
      sprintf(
        paste(
          "VB max_iter = %d cannot satisfy the RHS global-scale schedule;",
          "at least %d iterations are required for the configured warmup,",
          "minimum global-scale updates, and one coefficient response."
        ),
        max_iter,
        minimum_rhs_convergence_iter
      ),
      call. = FALSE
    )
  }
  future_moment_strategy <- app_latent_future_moment_strategy(vb_args)
  future_objective_strategy <- app_latent_future_objective_strategy(vb_args)
  future_update_strategy <- app_latent_future_update_strategy(vb_args)
  chunking <- app_latent_normalize_chunking_control(vb_args$chunking %||% NULL)
  profile_substeps <- isTRUE(diagnostics_args$profile_substeps %||% vb_args$profile_substeps %||% FALSE)
  draw_backend <- tolower(as.character(
    vb_args$draw_backend %||%
      diagnostics_args$draw_backend %||%
      "chol_eigen_fallback"
  )[[1L]])
  trace_iterations <- isTRUE(chunking$trace) ||
    isTRUE(diagnostics_args$trace_iterations %||% FALSE)
  if (identical(future_update_strategy, "linearized_delta") &&
      !identical(future_moment_strategy, "streamed_grouped")) {
    stop("The linearized Delta future update requires future_moment_strategy = 'streamed_grouped'.", call. = FALSE)
  }

  iteration_timing <- list()
  substep_timing <- list()
  time_step <- function(iter, step, expr) {
    start <- proc.time()[["elapsed"]]
    value <- force(expr)
    elapsed <- proc.time()[["elapsed"]] - start
    iter_value <- suppressWarnings(as.integer(iter %||% NA_integer_))
    iteration_timing[[length(iteration_timing) + 1L]] <<- data.frame(
      iteration = iter_value,
      step = step,
      elapsed_seconds = as.numeric(elapsed),
      stringsAsFactors = FALSE
    )
    if (isTRUE(trace_iterations)) {
      message(sprintf(
        "[latent-path VB] iter=%s step=%s elapsed=%.3fs chunking=%s chunk_size=%s",
        if (is.na(iter_value)) "post" else as.character(iter_value),
        step,
        elapsed,
        if (isTRUE(chunking$enabled)) "exact" else "none",
        as.character(chunking$chunk_size %||% NA_integer_)
      ))
    }
    value
  }
  append_substeps <- function(iter, parent_step, timing) {
    if (!isTRUE(profile_substeps) || is.null(timing) || !nrow(timing)) return(invisible(NULL))
    iter_value <- suppressWarnings(as.integer(iter %||% NA_integer_))
    timing$iteration <- iter_value
    timing$parent_step <- parent_step
    timing <- timing[, c("iteration", "parent_step", "step", "elapsed_seconds"), drop = FALSE]
    substep_timing[[length(substep_timing) + 1L]] <<- timing
    invisible(NULL)
  }

  checkpoint_cfg <- if (exists("app_latent_checkpoint_config", mode = "function")) {
    app_latent_checkpoint_config(vb_args)
  } else {
    list(enabled = FALSE, resume = FALSE)
  }
  if (isTRUE(checkpoint_cfg$enabled) && !nzchar(checkpoint_cfg$path %||% "")) {
    stop("Exact checkpointing is enabled but checkpoint.path is empty.", call. = FALSE)
  }
  if (is.finite(stop_after_iteration) && !isTRUE(checkpoint_cfg$enabled)) {
    stop("A controlled iteration stop requires exact checkpointing to be enabled.", call. = FALSE)
  }
  runtime_backend <- if (exists("app_latent_runtime_backend_manifest", mode = "function")) {
    app_latent_runtime_backend_manifest(fail_closed = TRUE)
  } else {
    data.frame(backend = "unrecorded", stringsAsFactors = FALSE)
  }
  checkpoint_contract <- if (isTRUE(checkpoint_cfg$enabled)) {
    app_latent_checkpoint_contract(
      design = design,
      p0 = p0,
      coefficient_prior = coefficient_prior,
      vb_args = vb_args,
      seed = seed
    )
  } else {
    NULL
  }
  checkpoint_diagnostics <- list(
    enabled = isTRUE(checkpoint_cfg$enabled),
    resumed = FALSE,
    recovered_previous = FALSE,
    source_path = NA_character_,
    path = checkpoint_cfg$path %||% NA_character_,
    contract_hash = checkpoint_contract$contract_hash %||% NA_character_,
    writes = 0L,
    write_seconds = 0,
    iteration_loaded = 0L,
    schema_version = checkpoint_cfg$schema_version %||% NA_character_
  )

  set.seed(seed)
  objective <- numeric(max_iter)
  par_change <- numeric(max_iter)
  repaired_theta <- logical(max_iter)
  rhs_gate_trace <- logical(max_iter)
  rhs_trace <- list()
  start_iter <- 1L

  if (isTRUE(checkpoint_cfg$enabled) && isTRUE(checkpoint_cfg$resume)) {
    checkpoint_payload <- app_latent_checkpoint_read(
      checkpoint_cfg$path,
      expected_contract = checkpoint_contract,
      allow_previous = isTRUE(checkpoint_cfg$keep_previous)
    )
    completed_iter <- as.integer(checkpoint_payload$iteration_completed)
    if (completed_iter >= max_iter) {
      stop(
        sprintf("Checkpoint already completed iteration %d for max_iter=%d.", completed_iter, max_iter),
        call. = FALSE
      )
    }
    if (is.finite(stop_after_iteration) && stop_after_iteration <= completed_iter) {
      stop(
        "diagnostics.stop_after_iteration must exceed the loaded checkpoint iteration.",
        call. = FALSE
      )
    }
    theta_mean <- as.numeric(checkpoint_payload$state$theta_mean)
    theta_cov <- as.matrix(checkpoint_payload$state$theta_cov)
    y_mean <- as.numeric(checkpoint_payload$state$y_mean)
    y_cov <- as.matrix(checkpoint_payload$state$y_cov)
    sigma_state <- checkpoint_payload$state$sigma_state
    v_state <- checkpoint_payload$state$v_state
    prior_state <- checkpoint_payload$state$prior_state
    warm_start <- checkpoint_payload$state$warm_start %||% list(
      diagnostics = list(enabled = FALSE, used = FALSE, message = "resumed exact checkpoint")
    )
    trace <- checkpoint_payload$traces
    if (completed_iter > 0L) {
      objective[seq_len(completed_iter)] <- as.numeric(trace$objective)
      par_change[seq_len(completed_iter)] <- as.numeric(trace$par_change)
      repaired_theta[seq_len(completed_iter)] <- as.logical(trace$repaired_theta)
      rhs_gate_trace[seq_len(completed_iter)] <- as.logical(trace$rhs_gate_trace)
    }
    rhs_trace <- trace$rhs_trace %||% list()
    if (is.data.frame(trace$iteration_timing) && nrow(trace$iteration_timing)) {
      iteration_timing <- list(trace$iteration_timing)
    }
    if (is.data.frame(trace$substep_timing) && nrow(trace$substep_timing)) {
      substep_timing <- list(trace$substep_timing)
    }
    if (!is.null(checkpoint_payload$rng_state) && length(checkpoint_payload$rng_state)) {
      assign(".Random.seed", checkpoint_payload$rng_state, envir = .GlobalEnv)
    }
    row_moments <- time_step(completed_iter, "resume_row_moments", {
      app_latent_row_moments(
        design, y_mean, y_cov, theta_mean, theta_cov,
        strategy = future_moment_strategy,
        profile_substeps = profile_substeps
      )
    })
    append_substeps(
      completed_iter,
      "resume_row_moments",
      attr(row_moments, "substep_timing", exact = TRUE)
    )
    start_iter <- completed_iter + 1L
    checkpoint_diagnostics$resumed <- TRUE
    checkpoint_diagnostics$recovered_previous <- isTRUE(attr(
      checkpoint_payload,
      "checkpoint_recovered_previous",
      exact = TRUE
    ))
    checkpoint_diagnostics$source_path <- attr(
      checkpoint_payload,
      "checkpoint_path",
      exact = TRUE
    ) %||% checkpoint_cfg$path
    checkpoint_diagnostics$iteration_loaded <- completed_iter
    prior_checkpoint_diag <- checkpoint_payload$metadata$checkpoint_diagnostics %||% list()
    checkpoint_diagnostics$writes <- as.integer(prior_checkpoint_diag$writes %||% 0L)
    checkpoint_diagnostics$write_seconds <- as.numeric(
      prior_checkpoint_diag$write_seconds %||% 0
    )
  } else {
    warm_start <- app_latent_path_warm_start_prepare(design, vb_args, p = p, H_future = H_future)
    theta_mean <- warm_start$theta_mean %||% rep(0, p)
    theta_cov <- warm_start$theta_cov %||% diag(1, p)
    y_mean <- warm_start$y_mean %||% as.numeric(design$y_future_init)
    y_cov <- warm_start$y_cov %||% diag(rep(stats::var(design$z_fixed, na.rm = TRUE) %||% 1, H_future))
    if (any(!is.finite(diag(y_cov))) || any(diag(y_cov) <= 0)) y_cov <- diag(1, H_future)

    prior_state <- time_step(NA_integer_, "prior_initialization", {
      app_latent_prior_state_init(
        p = p,
        prior = coefficient_prior,
        intercept_index = design$intercept_index,
        vb_args = vb_args,
        beta_index = design$beta_index %||% NULL,
        alpha_index = design$alpha_index %||% NULL
      )
    })
    if (isTRUE(warm_start$diagnostics$theta_used)) {
      prior_state <- time_step(NA_integer_, "warm_start_prior_update", {
        app_latent_prior_state_update(
          prior_state,
          theta_mean,
          theta_cov,
          iter = 0L,
          update_global = rhs_control$freeze_tau_warmup_iters == 0L
        )
      })
    }
    row_moments <- time_step(NA_integer_, "initial_row_moments", {
      app_latent_row_moments(
        design, y_mean, y_cov, theta_mean, theta_cov,
        strategy = future_moment_strategy,
        profile_substeps = profile_substeps
      )
    })
    append_substeps(NA_integer_, "initial_row_moments", attr(row_moments, "substep_timing", exact = TRUE))
    sigma_state <- if (!is.null(warm_start$sigma_state)) {
      time_step(NA_integer_, "warm_start_sigma_initialization", {
        warm_start$sigma_state
      })
    } else {
      time_step(NA_integer_, "sigma_initialization", {
        app_latent_source_sigma_init(row_moments$source, vb_args$prior_sigma %||% list(a = 2, b = 1))
      })
    }
    v_state <- time_step(NA_integer_, "initial_v_update", {
      app_latent_update_v(row_moments, sigma_state, constants)
    })
  }

  last_checkpoint_time <- proc.time()[["elapsed"]]
  completed_iterations <- start_iter - 1L
  write_checkpoint <- function(iter, force = FALSE) {
    if (!isTRUE(checkpoint_cfg$enabled)) return(invisible(FALSE))
    elapsed_since <- proc.time()[["elapsed"]] - last_checkpoint_time
    due <- isTRUE(force) ||
      (iter %% checkpoint_cfg$every_iterations == 0L) ||
      (is.finite(checkpoint_cfg$every_seconds) && elapsed_since >= checkpoint_cfg$every_seconds)
    if (!isTRUE(due)) return(invisible(FALSE))
    iteration_timing_df <- if (length(iteration_timing)) {
      do.call(rbind, iteration_timing)
    } else {
      data.frame(iteration = integer(), step = character(), elapsed_seconds = numeric())
    }
    substep_timing_df <- if (length(substep_timing)) {
      do.call(rbind, substep_timing)
    } else {
      data.frame(
        iteration = integer(), parent_step = character(), step = character(),
        elapsed_seconds = numeric()
      )
    }
    payload <- app_latent_checkpoint_payload(
      contract = checkpoint_contract,
      iteration_completed = iter,
      state = list(
        theta_mean = theta_mean,
        theta_cov = theta_cov,
        y_mean = y_mean,
        y_cov = y_cov,
        sigma_state = sigma_state,
        v_state = v_state,
        prior_state = prior_state,
        warm_start = warm_start
      ),
      traces = list(
        objective = objective[seq_len(iter)],
        par_change = par_change[seq_len(iter)],
        repaired_theta = repaired_theta[seq_len(iter)],
        rhs_gate_trace = rhs_gate_trace[seq_len(iter)],
        rhs_trace = rhs_trace,
        iteration_timing = iteration_timing_df,
        substep_timing = substep_timing_df
      ),
      rng_state = get(".Random.seed", envir = .GlobalEnv, inherits = FALSE),
      metadata = list(
        checkpoint_diagnostics = modifyList(
          checkpoint_diagnostics,
          list(writes = checkpoint_diagnostics$writes + 1L)
        ),
        runtime_backend = runtime_backend
      )
    )
    write_started <- proc.time()[["elapsed"]]
    app_latent_checkpoint_write(
      payload,
      checkpoint_cfg$path,
      compress = checkpoint_cfg$compress,
      keep_previous = checkpoint_cfg$keep_previous
    )
    write_elapsed <- proc.time()[["elapsed"]] - write_started
    checkpoint_diagnostics$writes <<- checkpoint_diagnostics$writes + 1L
    checkpoint_diagnostics$write_seconds <<- checkpoint_diagnostics$write_seconds + write_elapsed
    checkpoint_diagnostics$last_iteration <<- as.integer(iter)
    checkpoint_diagnostics$last_written_at <<- format(Sys.time(), tz = "UTC", usetz = TRUE)
    iteration_timing[[length(iteration_timing) + 1L]] <<- data.frame(
      iteration = as.integer(iter),
      step = "checkpoint_write",
      elapsed_seconds = as.numeric(write_elapsed),
      stringsAsFactors = FALSE
    )
    last_checkpoint_time <<- proc.time()[["elapsed"]]
    invisible(TRUE)
  }
  for (iter in seq.int(start_iter, max_iter)) {
    old <- c(theta_mean, y_mean, sigma_state$inv_mean)
    theta_update <- time_step(iter, "theta_update", {
      app_latent_update_theta(
        row_moments,
        v_state$inv_mean,
        sigma_state,
        constants,
        prior_state,
        chunking = chunking,
        profile_substeps = profile_substeps
      )
    })
    append_substeps(iter, "theta_update", attr(theta_update, "substep_timing", exact = TRUE))
    theta_mean <- as.numeric(theta_update$mean)
    theta_cov <- (theta_update$cov + t(theta_update$cov)) / 2
    repaired_theta[[iter]] <- isTRUE(theta_update$repaired)

    future_update <- time_step(iter, "future_update", {
      if (identical(future_update_strategy, "linearized_delta")) {
        app_latent_update_future_gaussian_delta(
          row_moments = row_moments,
          y_start = y_mean,
          theta_mean = theta_mean,
          theta_cov = theta_cov,
          e_inv_v = v_state$inv_mean,
          sigma_state = sigma_state,
          constants = constants
        )
      } else {
        app_latent_update_future_gaussian(
          y_start = y_mean,
          design = design,
          theta_mean = theta_mean,
          theta_cov = theta_cov,
          e_inv_v = v_state$inv_mean,
          sigma_state = sigma_state,
          constants = constants,
          objective_strategy = future_objective_strategy
        )
      }
    })
    y_mean <- future_update$mean
    y_cov <- future_update$cov

    row_moments <- time_step(iter, "row_moments", {
      app_latent_row_moments(
        design, y_mean, y_cov, theta_mean, theta_cov,
        strategy = future_moment_strategy,
        profile_substeps = profile_substeps
      )
    })
    append_substeps(iter, "row_moments", attr(row_moments, "substep_timing", exact = TRUE))
    v_state <- time_step(iter, "v_update", {
      app_latent_update_v(row_moments, sigma_state, constants)
    })
    sigma_state <- time_step(iter, "sigma_update", {
      app_latent_update_sigma(
        row_moments,
        e_v = v_state$mean,
        e_inv_v = v_state$inv_mean,
        constants = constants,
        prior_sigma = vb_args$prior_sigma %||% list(a = 2, b = 1),
        chunking = chunking
      )
    })
    prior_state <- time_step(iter, "prior_update", {
      app_latent_prior_state_update(prior_state, theta_mean, theta_cov, iter = iter)
    })
    rhs_trace[[length(rhs_trace) + 1L]] <- app_latent_prior_rhs_trace(prior_state, iter)
    rhs_gate <- app_latent_prior_rhs_gate(prior_state, iter)
    rhs_gate_trace[[iter]] <- isTRUE(rhs_gate$passed)

    objective[[iter]] <- time_step(iter, "objective", {
      app_latent_approx_objective(
        row_moments, v_state$mean, v_state$inv_mean, sigma_state,
        constants, theta_mean, theta_cov, prior_state
      )
    })
    new <- c(theta_mean, y_mean, sigma_state$inv_mean)
    par_change[[iter]] <- max(abs(new - old) / pmax(1, abs(old)))
    completed_iterations <- iter
    converged_now <- !isTRUE(fixed_iterations) && iter >= min_iter && isTRUE(rhs_gate$passed) &&
      is.finite(par_change[[iter]]) && par_change[[iter]] < tol
    controlled_stop_now <- is.finite(stop_after_iteration) && iter >= stop_after_iteration
    write_checkpoint(iter, force = isTRUE(converged_now) || isTRUE(controlled_stop_now) || iter == max_iter)
    if (isTRUE(controlled_stop_now)) {
      app_latent_checkpoint_stop(iter, checkpoint_cfg$path)
    }
    if (isTRUE(converged_now)) {
      break
    }
  }

  objective <- objective[seq_len(completed_iterations)]
  par_change <- par_change[seq_len(completed_iterations)]
  repaired_theta <- repaired_theta[seq_len(completed_iterations)]
  rhs_gate_trace <- rhs_gate_trace[seq_len(completed_iterations)]

  rhs_trace <- rhs_trace[vapply(rhs_trace, nrow, integer(1L)) > 0L]
  rhs_trace_df <- if (length(rhs_trace)) {
    do.call(rbind, rhs_trace)
  } else {
    data.frame()
  }
  rhs_diagnostics <- app_latent_prior_rhs_diagnostics(prior_state, length(objective))
  final_converged <- !isTRUE(fixed_iterations) && isTRUE(rhs_diagnostics$convergence_gate_passed) &&
    is.finite(tail(par_change, 1L)) && tail(par_change, 1L) < tol

  theta_draws <- time_step(NA_integer_, "theta_draw_generation", {
    app_latent_mvn_draws_exact(theta_mean, theta_cov, n_draws, seed = seed + 11L, backend = draw_backend)
  })
  theta_draw_backend <- attr(theta_draws, "backend", exact = TRUE) %||% NA_character_
  append_substeps(NA_integer_, "theta_draw_generation", attr(theta_draws, "substep_timing", exact = TRUE))
  y_draws <- time_step(NA_integer_, "future_draw_generation", {
    app_latent_mvn_draws_exact(y_mean, y_cov, n_draws, seed = seed + 17L, backend = draw_backend)
  })
  y_draw_backend <- attr(y_draws, "backend", exact = TRUE) %||% NA_character_
  append_substeps(NA_integer_, "future_draw_generation", attr(y_draws, "substep_timing", exact = TRUE))
  sigma_draws <- time_step(NA_integer_, "sigma_draw_generation", {
    cbind(
      sigma_Y = 1 / stats::rgamma(n_draws, shape = sigma_state$shape[["Y"]], rate = sigma_state$rate[["Y"]]),
      sigma_G = 1 / stats::rgamma(n_draws, shape = sigma_state$shape[["G"]], rate = sigma_state$rate[["G"]])
    )
  })

  colnames(theta_draws) <- colnames(design$H_fixed)
  colnames(y_draws) <- sprintf("y_future_%02d", seq_len(ncol(y_draws)))
  iteration_timing_df <- if (length(iteration_timing)) {
    do.call(rbind, iteration_timing)
  } else {
    data.frame(iteration = integer(), step = character(), elapsed_seconds = numeric())
  }
  substep_timing_df <- if (length(substep_timing)) {
    do.call(rbind, substep_timing)
  } else {
    data.frame(iteration = integer(), parent_step = character(), step = character(), elapsed_seconds = numeric())
  }
  checkpoint_diagnostics$removed_on_success <- FALSE
  if (isTRUE(checkpoint_cfg$enabled) && !isTRUE(checkpoint_cfg$keep_on_success)) {
    app_latent_checkpoint_remove(checkpoint_cfg$path)
    checkpoint_diagnostics$removed_on_success <- TRUE
  }
  list(
    method = "vb",
    likelihood_family = "al",
    prior = coefficient_prior,
    summary = list(
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      sigma_mean = sigma_state$mean,
      y_future_mean = y_mean,
      y_future_cov = y_cov
    ),
    draws = list(
      theta = theta_draws,
      sigma = sigma_draws,
      y_future = y_draws
    ),
    vb_diagnostics = list(
      converged = final_converged,
      iterations = length(objective),
      elbo_final = tail(objective, 1L),
      elbo_trace = objective,
      max_parameter_change = tail(par_change, 1L),
      parameter_change_trace = par_change,
      rhs_global_scale = rhs_diagnostics,
      rhs_global_scale_trace = rhs_trace_df,
      rhs_convergence_gate_trace = rhs_gate_trace,
      rhs_minimum_convergence_iteration = minimum_rhs_convergence_iter,
      theta_precision_repaired = any(repaired_theta),
      future_moment_strategy = future_moment_strategy,
      future_update_strategy = future_update_strategy,
      future_objective_strategy = future_objective_strategy,
      chunking = chunking,
      draw_backend_requested = draw_backend,
      theta_draw_backend = theta_draw_backend,
      future_draw_backend = y_draw_backend,
      iteration_timing = iteration_timing_df,
      substep_timing = substep_timing_df,
      warm_start = warm_start$diagnostics,
      fixed_iterations = fixed_iterations,
      checkpoint = checkpoint_diagnostics,
      runtime_backend = runtime_backend,
      objective_type = "first_order_delta_expected_log_joint"
    ),
    variational_state = list(
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      y_future_mean = y_mean,
      y_future_cov = y_cov,
      sigma = sigma_state,
      v = v_state,
      prior = prior_state,
      future_linearization = app_latent_extract_future_linearization(row_moments, design)
    )
  )
}
