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

app_latent_rhs_state_init <- function(p, intercept_index, args) {
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
    e_inv_zeta2 = a_zeta / b_zeta
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

app_latent_rhs_state_update <- function(state, theta_mean, theta_cov) {
  p <- length(theta_mean)
  e_theta2 <- as.numeric(theta_mean^2 + diag(theta_cov))
  idx <- state$penalized
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

  tau_shape <- (length(idx) + 1) / 2
  tau_rate <- pmax(state$e_inv_xi + 0.5 * sum(e_theta2[idx] * state$e_inv_lambda2[idx]), 1.0e-12)
  state$e_inv_tau2 <- tau_shape / tau_rate

  xi_shape <- 1
  xi_rate <- pmax(1 / state$tau0^2 + state$e_inv_tau2, 1.0e-12)
  state$e_inv_xi <- xi_shape / xi_rate

  zeta_shape <- state$a_zeta + length(idx) / 2
  zeta_rate <- pmax(state$b_zeta + 0.5 * sum(e_theta2[idx]), 1.0e-12)
  state$e_inv_zeta2 <- zeta_shape / zeta_rate

  state$prior_precision <- app_latent_rhs_prior_precision(state, p)
  state
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
        args = beta_args
      )
      alpha_state <- app_latent_rhs_state_init(
        p = length(alpha_index),
        intercept_index = app_latent_prior_block_intercepts(alpha_index, intercept_index),
        args = alpha_args
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
    return(app_latent_rhs_state_init(p, intercept_index, vb_args$beta_rhs %||% list()))
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

app_latent_prior_state_update <- function(state, theta_mean, theta_cov) {
  if (identical(state$prior, "rhs_ns")) return(app_latent_rhs_state_update(state, theta_mean, theta_cov))
  if (identical(state$prior, "block_rhs_ns")) {
    for (block_name in names(state$blocks)) {
      idx <- state$blocks[[block_name]]$global_index
      state$blocks[[block_name]]$state <- app_latent_rhs_state_update(
        state = state$blocks[[block_name]]$state,
        theta_mean = as.numeric(theta_mean[idx]),
        theta_cov = as.matrix(theta_cov[idx, idx, drop = FALSE])
      )
    }
    state$prior_precision <- app_latent_prior_state_combine_precision(state, length(theta_mean))
    return(state)
  }
  state
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

app_latent_trace_S_theta_parts <- function(h, J, y_cov, theta_mean, theta_cov) {
  h <- as.numeric(h)
  theta_mean <- as.numeric(theta_mean)
  theta_cov <- as.matrix(theta_cov)
  out <- app_latent_quad_theta(h, theta_mean, theta_cov)
  J <- as.matrix(J)
  if (nrow(J) && ncol(J) && any(J != 0) && any(y_cov != 0)) {
    J_cov <- theta_cov %*% J
    cov_part <- sum(y_cov * crossprod(J, J_cov))
    j_mean <- as.numeric(crossprod(J, theta_mean))
    mean_part <- as.numeric(crossprod(j_mean, y_cov %*% j_mean))
    out <- out + cov_part + mean_part
  }
  out
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

app_latent_fixed_block_design <- function(design = NULL, fixed = NULL, verify_dense = TRUE, tol = 1.0e-10) {
  source <- NULL
  beta_index <- NULL
  alpha_index <- NULL
  H <- NULL
  X_beta <- NULL
  X_alpha <- NULL
  if (!is.null(fixed) && !is.null(fixed$block)) {
    block <- fixed$block
    source <- as.character(block$source)
    beta_index <- as.integer(block$beta_index)
    alpha_index <- as.integer(block$alpha_index)
    X_beta <- as.matrix(block$X_beta_stack)
    X_alpha <- as.matrix(block$X_alpha_stack)
    H <- if (!is.null(fixed$H)) as.matrix(fixed$H) else NULL
  } else if (!is.null(design)) {
    source <- as.character(design$source_fixed)
    beta_index <- as.integer(design$beta_index %||% integer(0))
    alpha_index <- as.integer(design$alpha_index %||% integer(0))
    H <- if (!is.null(design$H_fixed)) as.matrix(design$H_fixed) else NULL
    if (!is.null(design$X_beta_stack)) {
      X_beta <- as.matrix(design$X_beta_stack)
    } else if (!is.null(H) && length(beta_index)) {
      X_beta <- H[, beta_index, drop = FALSE]
    }
    if (!is.null(design$X_alpha_stack)) {
      X_alpha <- as.matrix(design$X_alpha_stack)
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
    app_latent_fixed_block_design(design = design)
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
  y_loop <- timer$time("future_y_loop", {
    R_y_local <- numeric(H_future)
    e_y_local <- numeric(H_future)
    b_y_local <- vector("list", H_future)
    trace_y_local <- numeric(H_future)
    for (h in seq_len(H_future)) {
      J <- as.matrix(J_y[[h]])
      if (!all(dim(J) == c(p, H_future))) {
        stop("Future Y Jacobian has incompatible dimensions.", call. = FALSE)
      }
      h_vec <- as.numeric(H_y[h, ])
      trace_y_local[[h]] <- app_latent_trace_S_theta_parts(h_vec, J, y_cov, theta_mean, theta_cov)
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
    for (h in seq_len(H_future)) {
      J <- as.matrix(J_g_key[[h]])
      if (!all(dim(J) == c(p, H_future))) {
        stop("Future GloFAS keyed Jacobian has incompatible dimensions.", call. = FALSE)
      }
      h_vec <- as.numeric(H_g_key[h, ])
      trace_g_local[[h]] <- app_latent_trace_S_theta_parts(h_vec, J, y_cov, theta_mean, theta_cov)
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
  if (length(y_idx)) {
    sig_y <- sigma_state$inv_mean[["Y"]]
    w_y <- as.numeric(sig_y * e_inv_v[y_idx] / constants$B)
    c_y <- as.numeric(sig_y / constants$B * (e_inv_v[y_idx] * fixed$z[y_idx] - constants$A))
    Xb_y <- Xb[y_idx, , drop = FALSE]
    y_stats <- timer$time("fixed_theta_y_beta", {
      list(
        precision = crossprod(Xb_y, Xb_y * w_y),
        rhs = as.numeric(crossprod(Xb_y, c_y))
      )
    })
    precision[beta, beta] <- precision[beta, beta] + y_stats$precision
    rhs[beta] <- rhs[beta] + y_stats$rhs
  }
  if (length(g_idx)) {
    sig_g <- sigma_state$inv_mean[["G"]]
    w_g <- as.numeric(sig_g * e_inv_v[g_idx] / constants$B)
    c_g <- as.numeric(sig_g / constants$B * (e_inv_v[g_idx] * fixed$z[g_idx] - constants$A))
    Xb_g <- Xb[g_idx, , drop = FALSE]
    Xa_g <- Xa[g_idx, , drop = FALSE]
    P_bb_g <- timer$time("fixed_theta_g_beta_beta", {
      crossprod(Xb_g, Xb_g * w_g)
    })
    P_ba_g <- timer$time("fixed_theta_g_beta_alpha", {
      crossprod(Xb_g, Xa_g * w_g)
    })
    P_aa_g <- timer$time("fixed_theta_g_alpha_alpha", {
      crossprod(Xa_g, Xa_g * w_g)
    })
    precision[beta, beta] <- precision[beta, beta] + P_bb_g
    precision[beta, alpha] <- precision[beta, alpha] + P_ba_g
    precision[alpha, beta] <- precision[alpha, beta] + t(P_ba_g)
    precision[alpha, alpha] <- precision[alpha, alpha] + P_aa_g
    rhs_g <- timer$time("fixed_theta_g_rhs", {
      list(
        beta = as.numeric(crossprod(Xb_g, c_g)),
        alpha = as.numeric(crossprod(Xa_g, c_g))
      )
    })
    rhs[beta] <- rhs[beta] + rhs_g$beta
    rhs[alpha] <- rhs[alpha] + rhs_g$alpha
  }
  if (!is.null(block$feature_names) && length(block$feature_names) == p) {
    dimnames(precision) <- list(block$feature_names, block$feature_names)
  }
  out <- list(precision = 0.5 * (precision + t(precision)), rhs = rhs)
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
    sig_g <- sigma_state$inv_mean[["G"]]
    g_index_by_h <- future$g_index_by_h %||%
      split(seq_along(future$g_future_index), factor(future$g_future_index, levels = seq_len(n_y)))
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
        rhs_g <- rhs_g + sig_g / constants$B * (h_vec * sum(einv * z) - constants$A * length(idx) * h_vec)
      }
      list(precision = precision_g, rhs = rhs_g)
    })
    precision <- precision + future_g_stats$precision
    rhs <- rhs + future_g_stats$rhs
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

app_fit_latent_path_al_vb_core <- function(design, p0, coefficient_prior = "rhs_ns", vb_args = list(), seed = NULL) {
  if (!identical(tolower(as.character(vb_args$likelihood_family %||% "al")), "al")) {
    stop("The article-side latent-path VB fitter currently supports AL likelihood only.", call. = FALSE)
  }
  p <- ncol(design$H_fixed)
  H_future <- nrow(design$future_key)
  if (!H_future) stop("Latent-path design has no future horizon.", call. = FALSE)

  constants <- app_latent_al_constants(p0)
  seed <- as.integer(seed %||% vb_args$seed %||% 20260513L)
  max_iter <- as.integer(vb_args$max_iter %||% 200L)
  min_iter <- as.integer(vb_args$min_iter_elbo %||% 5L)
  tol <- as.numeric(vb_args$tol %||% 1.0e-4)
  n_draws <- as.integer(vb_args$n_draws %||% 500L)
  if (!is.finite(max_iter) || max_iter < 1L) max_iter <- 200L
  if (!is.finite(n_draws) || n_draws < 1L) n_draws <- 500L
  future_moment_strategy <- app_latent_future_moment_strategy(vb_args)
  future_objective_strategy <- app_latent_future_objective_strategy(vb_args)
  future_update_strategy <- app_latent_future_update_strategy(vb_args)
  chunking <- app_latent_normalize_chunking_control(vb_args$chunking %||% NULL)
  diagnostics_args <- vb_args$diagnostics %||% list()
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

  set.seed(seed)
  theta_mean <- rep(0, p)
  theta_cov <- diag(1, p)
  y_mean <- as.numeric(design$y_future_init)
  y_cov <- diag(rep(stats::var(design$z_fixed, na.rm = TRUE) %||% 1, H_future))
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
  row_moments <- time_step(NA_integer_, "initial_row_moments", {
    app_latent_row_moments(
      design, y_mean, y_cov, theta_mean, theta_cov,
      strategy = future_moment_strategy,
      profile_substeps = profile_substeps
    )
  })
  append_substeps(NA_integer_, "initial_row_moments", attr(row_moments, "substep_timing", exact = TRUE))
  sigma_state <- time_step(NA_integer_, "sigma_initialization", {
    app_latent_source_sigma_init(row_moments$source, vb_args$prior_sigma %||% list(a = 2, b = 1))
  })
  v_state <- time_step(NA_integer_, "initial_v_update", {
    app_latent_update_v(row_moments, sigma_state, constants)
  })
  objective <- numeric(max_iter)
  par_change <- numeric(max_iter)
  repaired_theta <- logical(max_iter)

  for (iter in seq_len(max_iter)) {
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
      app_latent_prior_state_update(prior_state, theta_mean, theta_cov)
    })

    objective[[iter]] <- time_step(iter, "objective", {
      app_latent_approx_objective(
        row_moments, v_state$mean, v_state$inv_mean, sigma_state,
        constants, theta_mean, theta_cov, prior_state
      )
    })
    new <- c(theta_mean, y_mean, sigma_state$inv_mean)
    par_change[[iter]] <- max(abs(new - old) / pmax(1, abs(old)))
    if (iter >= min_iter && is.finite(par_change[[iter]]) && par_change[[iter]] < tol) {
      objective <- objective[seq_len(iter)]
      par_change <- par_change[seq_len(iter)]
      repaired_theta <- repaired_theta[seq_len(iter)]
      break
    }
  }

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
      converged = tail(par_change, 1L) < tol,
      iterations = length(objective),
      elbo_final = tail(objective, 1L),
      elbo_trace = objective,
      max_parameter_change = tail(par_change, 1L),
      parameter_change_trace = par_change,
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
