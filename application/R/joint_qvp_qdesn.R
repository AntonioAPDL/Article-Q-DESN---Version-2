# Joint multi-quantile QVP helpers for prototype Q-DESN extensions.

app_joint_qvp_validate_tau_grid <- function(tau, label = "quantile grid") {
  if (is.data.frame(tau)) {
    if (!"quantile_level" %in% names(tau)) {
      stop(sprintf("%s must contain a quantile_level column.", label), call. = FALSE)
    }
    tau <- tau$quantile_level
  }
  tau <- as.numeric(tau)
  if (!length(tau)) stop(sprintf("%s is empty.", label), call. = FALSE)
  if (any(!is.finite(tau)) || any(tau <= 0 | tau >= 1)) {
    stop(sprintf("%s must contain finite values in (0, 1).", label), call. = FALSE)
  }
  if (is.unsorted(tau, strictly = TRUE)) {
    stop(sprintf("%s must be strictly increasing.", label), call. = FALSE)
  }
  tau
}

app_joint_qvp_check_design <- function(Z) {
  Z <- as.matrix(Z)
  storage.mode(Z) <- "double"
  if (!length(Z) || any(dim(Z) == 0L)) {
    stop("QVP design matrix must have positive dimensions.", call. = FALSE)
  }
  if (any(!is.finite(Z))) {
    stop("QVP design matrix contains non-finite values.", call. = FALSE)
  }
  Z
}

app_joint_qvp_al_constants <- function(tau) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  data.frame(
    tau = tau,
    A = (1 - 2 * tau) / (tau * (1 - tau)),
    B = 2 / (tau * (1 - tau)),
    lambda = rep(0, length(tau)),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_exal_support <- function(tau, upper = 50) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  gfun <- function(gamma) {
    exp(log(2) + stats::pnorm(-abs(gamma), log.p = TRUE) + gamma^2 / 2)
  }
  rows <- lapply(tau, function(p0) {
    lower <- stats::uniroot(function(x) gfun(x) - (1 - p0), c(-upper, -1.0e-10))$root
    upper_root <- stats::uniroot(function(x) gfun(x) - p0, c(1.0e-10, upper))$root
    c(lower = lower, upper = upper_root)
  })
  out <- as.data.frame(do.call(rbind, rows))
  out$tau <- tau
  out[, c("tau", "lower", "upper")]
}

app_joint_qvp_exal_constants <- function(tau, gamma) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  gamma <- as.numeric(gamma)
  if (length(gamma) == 1L) gamma <- rep(gamma, length(tau))
  if (length(gamma) != length(tau)) {
    stop("gamma must have length 1 or length(tau).", call. = FALSE)
  }
  support <- app_joint_qvp_exal_support(tau)
  if (any(!is.finite(gamma)) || any(gamma <= support$lower | gamma >= support$upper)) {
    stop("gamma contains values outside the exAL support.", call. = FALSE)
  }
  near_zero <- abs(gamma) < 1.0e-10
  out <- app_joint_qvp_al_constants(tau)
  if (any(!near_zero)) {
    idx <- which(!near_zero)
    gval <- exp(log(2) + stats::pnorm(-abs(gamma[idx]), log.p = TRUE) + gamma[idx]^2 / 2)
    ind_neg <- as.numeric(gamma[idx] < 0)
    ind_pos <- as.numeric(gamma[idx] > 0)
    p_gamma <- ind_neg + (tau[idx] - ind_neg) / gval
    out$A[idx] <- (1 - 2 * p_gamma) / (p_gamma * (1 - p_gamma))
    out$B[idx] <- 2 / (p_gamma * (1 - p_gamma))
    out$lambda[idx] <- abs(gamma[idx]) / (ind_pos - p_gamma)
  }
  out$gamma <- gamma
  out
}

app_joint_qvp_default_gamma <- function(tau) {
  support <- app_joint_qvp_exal_support(tau)
  # Start away from zero so the exAL-specific sigma block is identifiable in
  # tiny smoke runs; the bounded slice update can still move it toward zero.
  gamma <- 0.25 * support$upper
  pmin(pmax(gamma, support$lower + 1.0e-8), support$upper - 1.0e-8)
}

app_joint_qvp_check_gamma <- function(tau, gamma) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  gamma <- as.numeric(gamma)
  if (length(gamma) == 1L) gamma <- rep(gamma, length(tau))
  if (length(gamma) != length(tau)) stop("gamma must have length 1 or length(tau).", call. = FALSE)
  support <- app_joint_qvp_exal_support(tau)
  if (any(!is.finite(gamma)) || any(gamma <= support$lower | gamma >= support$upper)) {
    stop("gamma contains values outside the exAL support.", call. = FALSE)
  }
  gamma
}

app_joint_qvp_build_difference_matrix <- function(K, p) {
  K <- as.integer(K)
  p <- as.integer(p)
  if (K < 1L || p < 1L) stop("K and p must be positive integers.", call. = FALSE)
  app_require_namespace("Matrix")
  n <- K * p
  rows <- integer()
  cols <- integer()
  vals <- numeric()
  for (k in seq_len(K)) {
    for (j in seq_len(p)) {
      row <- (k - 1L) * p + j
      col <- row
      rows <- c(rows, row)
      cols <- c(cols, col)
      vals <- c(vals, 1)
      if (k > 1L) {
        rows <- c(rows, row)
        cols <- c(cols, (k - 2L) * p + j)
        vals <- c(vals, -1)
      }
    }
  }
  Matrix::sparseMatrix(i = rows, j = cols, x = vals, dims = c(n, n))
}

app_joint_qvp_apply_difference <- function(beta, K, p) {
  beta <- as.numeric(beta)
  if (length(beta) != K * p) {
    stop("beta length does not match K * p.", call. = FALSE)
  }
  as.numeric(app_joint_qvp_build_difference_matrix(K, p) %*% beta)
}

app_joint_qvp_build_stacked_design <- function(Z, K) {
  Z <- app_joint_qvp_check_design(Z)
  K <- as.integer(K)
  if (K < 1L) stop("K must be positive.", call. = FALSE)
  app_require_namespace("Matrix")
  blocks <- replicate(K, Matrix::Matrix(Z, sparse = TRUE), simplify = FALSE)
  Matrix::bdiag(blocks)
}

app_joint_qvp_rhs_ns_precision <- function(lambda2, tau2, zeta2 = Inf, p = NULL) {
  if (!is.null(p)) {
    p <- as.integer(p)
    if (length(lambda2) == 1L) lambda2 <- rep(lambda2, p)
  }
  lambda2 <- as.numeric(lambda2)
  tau2 <- as.numeric(tau2)[[1L]]
  zeta2 <- as.numeric(zeta2)[[1L]]
  if (!length(lambda2) || any(!is.finite(lambda2)) || any(lambda2 <= 0)) {
    stop("lambda2 must be positive and finite.", call. = FALSE)
  }
  if (!is.finite(tau2) || tau2 <= 0) stop("tau2 must be positive and finite.", call. = FALSE)
  slab_prec <- if (is.finite(zeta2)) {
    if (zeta2 <= 0) stop("zeta2 must be positive when finite.", call. = FALSE)
    1 / zeta2
  } else {
    0
  }
  1 / (tau2 * lambda2) + slab_prec
}

app_joint_qvp_recycle_blocks <- function(block, n_blocks, p, label) {
  if (n_blocks == 0L) return(list())
  if (is.list(block) && length(block) == n_blocks && is.null(block$tau2)) {
    return(block)
  }
  if (!is.list(block)) stop(sprintf("%s must be a list.", label), call. = FALSE)
  replicate(n_blocks, block, simplify = FALSE)
}

app_joint_qvp_build_prior_precision <- function(K, p, anchor, innovations = NULL) {
  K <- as.integer(K)
  p <- as.integer(p)
  if (K < 1L || p < 1L) stop("K and p must be positive.", call. = FALSE)
  app_require_namespace("Matrix")
  anchor_prec <- app_joint_qvp_rhs_ns_precision(
    lambda2 = anchor$lambda2 %||% rep(1, p),
    tau2 = anchor$tau2 %||% 1,
    zeta2 = anchor$zeta2 %||% Inf,
    p = p
  )
  blocks <- list(Matrix::Diagonal(x = anchor_prec))
  block_precisions <- list(anchor = anchor_prec)
  if (K > 1L) {
    innovations <- innovations %||% list(lambda2 = rep(1, p), tau2 = 1, zeta2 = Inf)
    innovation_blocks <- app_joint_qvp_recycle_blocks(innovations, K - 1L, p, "innovations")
    for (i in seq_along(innovation_blocks)) {
      prec <- app_joint_qvp_rhs_ns_precision(
        lambda2 = innovation_blocks[[i]]$lambda2 %||% rep(1, p),
        tau2 = innovation_blocks[[i]]$tau2 %||% 1,
        zeta2 = innovation_blocks[[i]]$zeta2 %||% Inf,
        p = p
      )
      blocks[[length(blocks) + 1L]] <- Matrix::Diagonal(x = prec)
      block_precisions[[paste0("delta_", i + 1L)]] <- prec
    }
  }
  P_delta <- Matrix::bdiag(blocks)
  H <- app_joint_qvp_build_difference_matrix(K, p)
  P_beta <- Matrix::forceSymmetric(Matrix::t(H) %*% P_delta %*% H)
  list(H = H, P_delta = P_delta, P_beta = P_beta, block_precisions = block_precisions)
}

app_joint_qvp_beta_matrix <- function(beta, K, p) {
  beta <- as.numeric(beta)
  if (length(beta) != K * p) stop("beta length does not match K * p.", call. = FALSE)
  matrix(beta, nrow = p, ncol = K)
}

app_joint_qvp_build_working_response <- function(
  y,
  Z,
  beta,
  alpha,
  tau,
  sigma,
  v,
  kappa = 1,
  likelihood = c("al", "exal"),
  gamma = NULL,
  s = NULL
) {
  likelihood <- match.arg(likelihood)
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  alpha <- as.numeric(alpha)
  sigma <- as.numeric(sigma)
  if (length(alpha) != K || length(sigma) != K) {
    stop("alpha and sigma must have length K.", call. = FALSE)
  }
  if (any(!is.finite(sigma)) || any(sigma <= 0)) stop("sigma must be positive.", call. = FALSE)
  if (!is.finite(kappa) || kappa <= 0) stop("kappa must be positive.", call. = FALSE)
  v <- as.matrix(v)
  storage.mode(v) <- "double"
  if (!identical(dim(v), c(Tn, K))) stop("v must have dimension length(y) by K.", call. = FALSE)
  if (any(!is.finite(v)) || any(v <= 0)) stop("v must be positive.", call. = FALSE)
  beta_mat <- app_joint_qvp_beta_matrix(beta, K, p)
  constants <- if (identical(likelihood, "al")) {
    app_joint_qvp_al_constants(tau)
  } else {
    if (is.null(gamma) || is.null(s)) stop("exAL working response requires gamma and s.", call. = FALSE)
    app_joint_qvp_exal_constants(tau, gamma)
  }
  if (identical(likelihood, "exal")) {
    s <- as.matrix(s)
    storage.mode(s) <- "double"
    if (!identical(dim(s), c(Tn, K))) stop("s must have dimension length(y) by K.", call. = FALSE)
    if (any(!is.finite(s)) || any(s < 0)) stop("s must be nonnegative.", call. = FALSE)
  } else {
    s <- matrix(0, nrow = Tn, ncol = K)
  }
  y_star <- numeric(Tn * K)
  weights <- numeric(Tn * K)
  qhat <- Z %*% beta_mat
  for (k in seq_len(K)) {
    idx <- ((k - 1L) * Tn + 1L):(k * Tn)
    y_star[idx] <- y - alpha[[k]] -
      constants$lambda[[k]] * sigma[[k]] * s[, k] -
      constants$A[[k]] * v[, k]
    weights[idx] <- kappa / (constants$B[[k]] * sigma[[k]] * v[, k])
  }
  list(
    y_star = y_star,
    weights = weights,
    Z_stack = app_joint_qvp_build_stacked_design(Z, K),
    qhat = qhat + matrix(alpha, nrow = Tn, ncol = K, byrow = TRUE),
    constants = constants,
    kappa = kappa,
    likelihood = likelihood
  )
}

app_joint_qvp_beta_gaussian_update <- function(Z_stack, y_star, weights, P_beta) {
  app_require_namespace("Matrix")
  weights <- as.numeric(weights)
  if (any(!is.finite(weights)) || any(weights <= 0)) stop("weights must be positive.", call. = FALSE)
  W <- Matrix::Diagonal(x = weights)
  K_beta <- Matrix::forceSymmetric(Matrix::t(Z_stack) %*% W %*% Z_stack + P_beta)
  rhs <- as.numeric(Matrix::t(Z_stack) %*% (weights * as.numeric(y_star)))
  mean <- as.numeric(Matrix::solve(K_beta, rhs))
  list(precision = K_beta, mean = mean)
}

app_joint_qvp_precision_draw <- function(mean, precision, max_dense_dim = 250L, force_sparse = FALSE) {
  d <- length(mean)
  if (d <= max_dense_dim && !isTRUE(force_sparse)) {
    R <- chol(as.matrix(precision))
    return(as.numeric(mean + backsolve(R, stats::rnorm(d))))
  }
  app_require_namespace("Matrix")
  fac <- Matrix::Cholesky(Matrix::forceSymmetric(precision), LDL = FALSE, perm = TRUE)
  expanded <- Matrix::expand(fac)
  z <- stats::rnorm(d)
  dev <- as.numeric(Matrix::t(expanded$P) %*% Matrix::solve(Matrix::t(expanded$L), z))
  as.numeric(mean + dev)
}

app_joint_qvp_crossing_diagnostics <- function(qhat, tau, tolerance = 1.0e-10) {
  qhat <- as.matrix(qhat)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (ncol(qhat) != length(tau)) stop("ncol(qhat) must equal length(tau).", call. = FALSE)
  rows <- lapply(seq_len(nrow(qhat)), function(i) {
    diffs <- diff(qhat[i, ])
    violations <- diffs < -tolerance
    data.frame(
      row_index = i,
      n_quantiles = length(tau),
      n_adjacent_pairs = length(diffs),
      n_crossing_pairs = sum(violations, na.rm = TRUE),
      max_crossing_magnitude = if (any(violations, na.rm = TRUE)) max(-diffs[violations], na.rm = TRUE) else 0,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_simulate_synthetic <- function(
  Tn = 40L,
  p = 3L,
  tau = c(0.25, 0.5, 0.75),
  scenario = c("parallel", "slope_variation", "crossing_pressure"),
  seed = NULL,
  noise_sd = 0.1
) {
  scenario <- match.arg(scenario)
  if (!is.null(seed)) set.seed(seed)
  Tn <- as.integer(Tn)
  p <- as.integer(p)
  if (Tn < 5L || p < 1L) stop("Synthetic fixture requires Tn >= 5 and p >= 1.", call. = FALSE)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  grid <- seq(-1, 1, length.out = Tn)
  Z <- matrix(0, nrow = Tn, ncol = p)
  Z[, 1L] <- grid
  if (p >= 2L) Z[, 2L] <- sin(seq(0, 2 * pi, length.out = Tn))
  if (p >= 3L) Z[, 3L] <- cos(seq(0, 2 * pi, length.out = Tn))
  if (p > 3L) {
    for (j in 4:p) Z[, j] <- grid^(j - 2L)
  }
  colnames(Z) <- paste0("x", seq_len(p))
  base_beta <- seq(0.35, -0.15, length.out = p)
  alpha <- as.numeric(stats::qnorm(tau)) * 0.4
  beta <- matrix(rep(base_beta, K), nrow = p, ncol = K)
  if (identical(scenario, "slope_variation")) {
    for (k in seq_len(K)) {
      beta[, k] <- base_beta + (k - (K + 1) / 2) * seq(0.05, -0.03, length.out = p)
    }
  } else if (identical(scenario, "crossing_pressure")) {
    alpha <- seq(-0.05, 0.05, length.out = K)
    beta <- matrix(0, nrow = p, ncol = K)
    beta[1L, ] <- seq(0.8, -0.8, length.out = K)
    if (p >= 2L) beta[2L, ] <- seq(-0.2, 0.2, length.out = K)
  }
  true_q <- Z %*% beta + matrix(alpha, nrow = Tn, ncol = K, byrow = TRUE)
  center_idx <- which.min(abs(tau - 0.5))
  y <- as.numeric(true_q[, center_idx] + stats::rnorm(Tn, sd = noise_sd))
  list(
    y = y,
    Z = Z,
    tau = tau,
    alpha = alpha,
    beta = beta,
    true_q = true_q,
    scenario = scenario,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(true_q, tau)
  )
}

app_joint_qvp_qal <- function(u, p = 0.5) {
  u <- as.numeric(u)
  p <- as.numeric(p)[[1L]]
  if (any(!is.finite(u)) || any(u <= 0 | u >= 1) || !is.finite(p) || p <= 0 || p >= 1) {
    stop("Asymmetric-Laplace quantiles require u and p in (0, 1).", call. = FALSE)
  }
  ifelse(
    u < p,
    log(u / p) / (1 - p),
    -log((1 - u) / (1 - p)) / p
  )
}

app_joint_qvp_al_sd <- function(p = 0.5) {
  p <- as.numeric(p)[[1L]]
  if (!is.finite(p) || p <= 0 || p >= 1) {
    stop("Asymmetric-Laplace skew parameter must be in (0, 1).", call. = FALSE)
  }
  sqrt((1 - 2 * p + 2 * p^2) / (p^2 * (1 - p)^2))
}

app_joint_qvp_standardized_innovation <- function(n, innovation = "student_t", df = 5, al_tau = 0.5) {
  innovation <- match.arg(innovation, c("student_t", "gaussian", "asymmetric_laplace"))
  n <- as.integer(n)
  if (n <= 0L) stop("n must be positive.", call. = FALSE)
  if (identical(innovation, "student_t")) {
    df <- as.numeric(df)[[1L]]
    if (!is.finite(df) || df <= 2) {
      stop("Student-t innovations require df > 2 for variance standardization.", call. = FALSE)
    }
    raw <- stats::rt(n, df = df)
    scale <- sqrt(df / (df - 2))
  } else if (identical(innovation, "gaussian")) {
    raw <- stats::rnorm(n)
    scale <- 1
  } else {
    raw <- app_joint_qvp_qal(stats::runif(n), p = al_tau)
    scale <- app_joint_qvp_al_sd(al_tau)
  }
  list(raw = raw, standardized = raw / scale, scale = scale)
}

app_joint_qvp_standardized_quantile <- function(tau, innovation = "student_t", df = 5, al_tau = 0.5) {
  innovation <- match.arg(innovation, c("student_t", "gaussian", "asymmetric_laplace"))
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (identical(innovation, "student_t")) {
    df <- as.numeric(df)[[1L]]
    if (!is.finite(df) || df <= 2) {
      stop("Student-t innovations require df > 2 for variance standardization.", call. = FALSE)
    }
    stats::qt(tau, df = df) / sqrt(df / (df - 2))
  } else if (identical(innovation, "gaussian")) {
    stats::qnorm(tau)
  } else {
    app_joint_qvp_qal(tau, p = al_tau) / app_joint_qvp_al_sd(al_tau)
  }
}

app_joint_qvp_simulate_ts_toy_synthetic <- function(
  Tn = 120L,
  tau = c(0.1, 0.5, 0.9),
  seed = NULL,
  df = 5,
  innovation = c("student_t", "gaussian", "asymmetric_laplace"),
  al_tau = 0.5,
  period = 24L,
  initial_y = 0,
  location_intercept = 0.1,
  beta_location = c(
    lag_y = 0.55,
    trend = 0.04,
    sin_season = 0.30,
    cos_season = -0.10,
    abs_lag_scaled = 0.00
  ),
  scale_intercept = 0.45,
  beta_scale = c(
    lag_y = 0.00,
    trend = 0.03,
    sin_season = 0.00,
    cos_season = 0.05,
    abs_lag_scaled = 0.08
  )
) {
  innovation <- match.arg(innovation)
  if (!is.null(seed)) set.seed(seed)
  Tn <- as.integer(Tn)
  period <- as.integer(period)
  if (Tn < 10L) stop("Time-series toy fixture requires Tn >= 10.", call. = FALSE)
  if (period < 2L) stop("period must be at least 2.", call. = FALSE)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  df <- as.numeric(df)[[1L]]
  if (identical(innovation, "student_t") && (!is.finite(df) || df <= 2)) {
    stop("Student-t time-series toy requires df > 2 for variance standardization.", call. = FALSE)
  }
  al_tau <- as.numeric(al_tau)[[1L]]
  if (identical(innovation, "asymmetric_laplace") && (!is.finite(al_tau) || al_tau <= 0 || al_tau >= 1)) {
    stop("asymmetric_laplace time-series toy requires al_tau in (0, 1).", call. = FALSE)
  }
  feature_names <- c("lag_y", "trend", "sin_season", "cos_season", "abs_lag_scaled")
  beta_location <- as.numeric(beta_location[feature_names])
  beta_scale <- as.numeric(beta_scale[feature_names])
  names(beta_location) <- feature_names
  names(beta_scale) <- feature_names
  if (any(is.na(beta_location)) || any(is.na(beta_scale))) {
    stop("beta_location and beta_scale must contain the required named toy features.", call. = FALSE)
  }
  location_intercept <- as.numeric(location_intercept)[[1L]]
  scale_intercept <- as.numeric(scale_intercept)[[1L]]
  initial_y <- as.numeric(initial_y)[[1L]]
  if (any(!is.finite(c(location_intercept, scale_intercept, initial_y, beta_location, beta_scale)))) {
    stop("Toy DGP parameters must be finite.", call. = FALSE)
  }
  trend <- seq(-1, 1, length.out = Tn)
  y <- numeric(Tn)
  Z <- matrix(NA_real_, nrow = Tn, ncol = length(feature_names), dimnames = list(NULL, feature_names))
  mu <- sigma <- innov_raw <- innov <- numeric(Tn)
  q_standardized <- app_joint_qvp_standardized_quantile(tau, innovation = innovation, df = df, al_tau = al_tau)
  innovations <- app_joint_qvp_standardized_innovation(Tn, innovation = innovation, df = df, al_tau = al_tau)
  for (tt in seq_len(Tn)) {
    lag_y <- if (tt == 1L) initial_y else y[[tt - 1L]]
    angle <- 2 * pi * (tt - 1L) / period
    Z[tt, ] <- c(
      lag_y = lag_y,
      trend = trend[[tt]],
      sin_season = sin(angle),
      cos_season = cos(angle),
      abs_lag_scaled = abs(lag_y) / (1 + abs(lag_y))
    )
    mu[[tt]] <- location_intercept + sum(beta_location * Z[tt, ])
    sigma[[tt]] <- scale_intercept + sum(beta_scale * Z[tt, ])
    if (!is.finite(sigma[[tt]]) || sigma[[tt]] <= 0) {
      stop("Toy DGP scale became non-positive; adjust scale parameters.", call. = FALSE)
    }
    innov_raw[[tt]] <- innovations$raw[[tt]]
    innov[[tt]] <- innovations$standardized[[tt]]
    y[[tt]] <- mu[[tt]] + sigma[[tt]] * innov[[tt]]
  }
  K <- length(tau)
  p <- ncol(Z)
  alpha <- location_intercept + scale_intercept * q_standardized
  beta <- matrix(rep(beta_location, K), nrow = p, ncol = K, dimnames = list(feature_names, paste0("tau_", tau))) +
    beta_scale %o% q_standardized
  true_q <- Z %*% beta + matrix(alpha, nrow = Tn, ncol = K, byrow = TRUE)
  colnames(true_q) <- paste0("q_tau_", gsub("[^0-9]+", "p", format(tau, trim = TRUE, scientific = FALSE)))
  list(
    y = y,
    Z = Z,
    tau = tau,
    alpha = as.numeric(alpha),
    beta = beta,
    true_q = true_q,
    mu = mu,
    sigma = sigma,
    innovation = innov,
    innovation_raw = innov_raw,
    q_standardized = q_standardized,
    df = df,
    innovation_scale = innovations$scale,
    al_tau = al_tau,
    period = period,
    initial_y = initial_y,
    location_intercept = location_intercept,
    scale_intercept = scale_intercept,
    beta_location = beta_location,
    beta_scale = beta_scale,
    dynamic = "ar1_seasonal_location_scale",
    likelihood = paste0("standardized_", innovation),
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(true_q, tau)
  )
}

app_joint_qvp_run_ts_toy_synthetic <- function(
  out_dir,
  Tn = 120L,
  tau = c(0.1, 0.5, 0.9),
  seed = 20260701L,
  df = 5,
  innovation = "student_t",
  al_tau = 0.5,
  period = 24L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fixture <- app_joint_qvp_simulate_ts_toy_synthetic(
    Tn = Tn,
    tau = tau,
    seed = seed,
    df = df,
    innovation = innovation,
    al_tau = al_tau,
    period = period
  )
  tau_label <- function(x) {
    paste0("tau_", gsub("[^0-9]+", "p", format(x, trim = TRUE, scientific = FALSE)))
  }
  observed <- data.frame(
    time_index = seq_len(length(fixture$y)),
    y = fixture$y,
    mu = fixture$mu,
    sigma = fixture$sigma,
    innovation = fixture$innovation,
    innovation_raw = fixture$innovation_raw,
    stringsAsFactors = FALSE
  )
  design <- data.frame(time_index = seq_len(nrow(fixture$Z)), fixture$Z, check.names = FALSE)
  true_quantiles <- data.frame(
    time_index = seq_len(nrow(fixture$true_q)),
    fixture$true_q,
    check.names = FALSE
  )
  quantile_long <- do.call(rbind, lapply(seq_along(fixture$tau), function(k) {
    data.frame(
      time_index = seq_len(nrow(fixture$true_q)),
      quantile_index = k,
      tau = fixture$tau[[k]],
      true_quantile = fixture$true_q[, k],
      stringsAsFactors = FALSE
    )
  }))
  readout_rows <- list()
  for (k in seq_along(fixture$tau)) {
    readout_rows[[length(readout_rows) + 1L]] <- data.frame(
      parameter = "alpha",
      feature = "intercept",
      quantile_index = k,
      tau = fixture$tau[[k]],
      value = fixture$alpha[[k]],
      stringsAsFactors = FALSE
    )
    readout_rows[[length(readout_rows) + 1L]] <- data.frame(
      parameter = "beta",
      feature = rownames(fixture$beta),
      quantile_index = k,
      tau = fixture$tau[[k]],
      value = fixture$beta[, k],
      stringsAsFactors = FALSE
    )
  }
  readout_parameters <- do.call(rbind, readout_rows)
  dgp_parameters <- rbind(
    data.frame(block = "scalar", name = "Tn", value = Tn, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "df", value = fixture$df, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "al_tau", value = fixture$al_tau, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "innovation_scale", value = fixture$innovation_scale, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "period", value = fixture$period, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "initial_y", value = fixture$initial_y, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "location_intercept", value = fixture$location_intercept, stringsAsFactors = FALSE),
    data.frame(block = "scalar", name = "scale_intercept", value = fixture$scale_intercept, stringsAsFactors = FALSE),
    data.frame(block = "beta_location", name = names(fixture$beta_location), value = fixture$beta_location, stringsAsFactors = FALSE),
    data.frame(block = "beta_scale", name = names(fixture$beta_scale), value = fixture$beta_scale, stringsAsFactors = FALSE),
    data.frame(block = "q_standardized", name = tau_label(fixture$tau), value = fixture$q_standardized, stringsAsFactors = FALSE)
  )
  run_config <- data.frame(
    run_id = "joint_qvp_ts_toy_synthetic",
    seed = seed,
    Tn = Tn,
    K = length(fixture$tau),
    tau = paste(fixture$tau, collapse = ","),
    dynamic = fixture$dynamic,
    likelihood = fixture$likelihood,
    df = fixture$df,
    al_tau = fixture$al_tau,
    innovation_scale = fixture$innovation_scale,
    period = fixture$period,
    feature_names = paste(colnames(fixture$Z), collapse = ","),
    true_quantile_contract = "true_q = Z %*% beta(tau) + alpha(tau)",
    stringsAsFactors = FALSE
  )
  crossing_summary <- cbind(
    data.frame(run_id = "joint_qvp_ts_toy_synthetic", stringsAsFactors = FALSE),
    fixture$crossing_diagnostics
  )
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    observed_series = app_joint_qvp_write_csv(observed, file.path(out_dir, "observed_series.csv")),
    design_matrix = app_joint_qvp_write_csv(design, file.path(out_dir, "design_matrix.csv")),
    true_quantiles = app_joint_qvp_write_csv(true_quantiles, file.path(out_dir, "true_quantiles.csv")),
    true_quantile_long = app_joint_qvp_write_csv(quantile_long, file.path(out_dir, "true_quantile_long.csv")),
    true_readout_parameters = app_joint_qvp_write_csv(readout_parameters, file.path(out_dir, "true_readout_parameters.csv")),
    dgp_parameters = app_joint_qvp_write_csv(dgp_parameters, file.path(out_dir, "dgp_parameters.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest, fixture = fixture)
}

app_joint_qvp_parse_named_numeric_spec <- function(x, default) {
  default_names <- names(default)
  if (is.null(default_names) || any(!nzchar(default_names))) {
    stop("default must be a named numeric vector.", call. = FALSE)
  }
  default <- as.numeric(default)
  names(default) <- default_names
  if (is.null(x) || length(x) == 0L || is.na(x[[1L]]) || !nzchar(as.character(x[[1L]]))) {
    return(default)
  }
  if (is.numeric(x)) {
    out <- as.numeric(x)
    if (is.null(names(x))) names(out) <- default_names
  } else {
    parts <- strsplit(as.character(x[[1L]]), ",", fixed = TRUE)[[1L]]
    out <- default
    for (part in parts) {
      kv <- strsplit(trimws(part), "=", fixed = TRUE)[[1L]]
      if (length(kv) != 2L) stop("Named numeric specs must use name=value pairs.", call. = FALSE)
      key <- trimws(kv[[1L]])
      val <- as.numeric(trimws(kv[[2L]]))
      if (!key %in% default_names || !is.finite(val)) {
        stop("Named numeric spec has an unknown key or non-finite value.", call. = FALSE)
      }
      out[[key]] <- val
    }
  }
  out <- out[default_names]
  if (length(out) != length(default) || any(!is.finite(out))) {
    stop("Named numeric spec did not resolve to a finite vector.", call. = FALSE)
  }
  out
}

app_joint_qvp_ts_default_beta_location <- function() {
  c(lag_y = 0.55, trend = 0.04, sin_season = 0.30, cos_season = -0.10, abs_lag_scaled = 0.00)
}

app_joint_qvp_ts_default_beta_scale <- function() {
  c(lag_y = 0.00, trend = 0.03, sin_season = 0.00, cos_season = 0.05, abs_lag_scaled = 0.08)
}

app_joint_qvp_default_ts_synthetic_scenarios <- function() {
  data.frame(
    case_id = c(
      "ts_student_t_lscale",
      "ts_gaussian_homoskedastic",
      "ts_student_t_heteroskedastic",
      "ts_asymmetric_laplace_tail",
      "ts_seasonal_low_ar",
      "ts_persistent_heavy_tail"
    ),
    Tn = c(120L, 96L, 120L, 120L, 96L, 120L),
    tau = c("0.1,0.5,0.9", "0.1,0.5,0.9", "0.1,0.5,0.9", "0.1,0.5,0.9", "0.1,0.5,0.9", "0.05,0.5,0.95"),
    seed = c(20260701L, 20260702L, 20260703L, 20260704L, 20260705L, 20260706L),
    innovation = c("student_t", "gaussian", "student_t", "asymmetric_laplace", "gaussian", "student_t"),
    df = c(5, 5, 4, 5, 5, 3.5),
    al_tau = c(0.5, 0.5, 0.5, 0.3, 0.5, 0.5),
    period = c(24L, 24L, 24L, 24L, 12L, 24L),
    location_intercept = c(0.10, 0.05, 0.10, 0.05, 0.00, 0.08),
    scale_intercept = c(0.45, 0.35, 0.45, 0.40, 0.32, 0.48),
    beta_location = c(
      "lag_y=0.55,trend=0.04,sin_season=0.30,cos_season=-0.10,abs_lag_scaled=0.00",
      "lag_y=0.35,trend=0.02,sin_season=0.25,cos_season=-0.08,abs_lag_scaled=0.00",
      "lag_y=0.50,trend=0.05,sin_season=0.28,cos_season=-0.12,abs_lag_scaled=0.04",
      "lag_y=0.45,trend=0.03,sin_season=0.32,cos_season=-0.05,abs_lag_scaled=0.02",
      "lag_y=0.15,trend=0.01,sin_season=0.55,cos_season=0.20,abs_lag_scaled=0.00",
      "lag_y=0.72,trend=0.02,sin_season=0.20,cos_season=-0.06,abs_lag_scaled=0.02"
    ),
    beta_scale = c(
      "lag_y=0.00,trend=0.03,sin_season=0.00,cos_season=0.05,abs_lag_scaled=0.08",
      "lag_y=0.00,trend=0.00,sin_season=0.00,cos_season=0.00,abs_lag_scaled=0.00",
      "lag_y=0.00,trend=0.08,sin_season=0.05,cos_season=0.06,abs_lag_scaled=0.15",
      "lag_y=0.00,trend=0.02,sin_season=0.03,cos_season=0.04,abs_lag_scaled=0.10",
      "lag_y=0.00,trend=0.02,sin_season=0.02,cos_season=0.03,abs_lag_scaled=0.05",
      "lag_y=0.00,trend=0.04,sin_season=0.02,cos_season=0.04,abs_lag_scaled=0.10"
    ),
    notes = c(
      "default dynamic location-scale Student-t toy",
      "Gaussian reference with constant scale",
      "heavy-tailed heteroskedastic reference",
      "right-tail asymmetric-Laplace innovation reference",
      "seasonal-dominant low-autoregression reference",
      "persistent heavy-tail wide-grid reference"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_ts_fixture_from_scenario <- function(sc) {
  default_loc <- app_joint_qvp_ts_default_beta_location()
  default_scale <- app_joint_qvp_ts_default_beta_scale()
  app_joint_qvp_simulate_ts_toy_synthetic(
    Tn = as.integer(sc$Tn[[1L]]),
    tau = app_joint_qvp_parse_tau_spec(sc$tau[[1L]], default = c(0.1, 0.5, 0.9)),
    seed = as.integer(sc$seed[[1L]]),
    df = as.numeric(sc$df[[1L]]),
    innovation = as.character(sc$innovation[[1L]]),
    al_tau = as.numeric(sc$al_tau[[1L]]),
    period = as.integer(sc$period[[1L]]),
    location_intercept = as.numeric(sc$location_intercept[[1L]]),
    scale_intercept = as.numeric(sc$scale_intercept[[1L]]),
    beta_location = app_joint_qvp_parse_named_numeric_spec(sc$beta_location[[1L]], default_loc),
    beta_scale = app_joint_qvp_parse_named_numeric_spec(sc$beta_scale[[1L]], default_scale)
  )
}

app_joint_qvp_ts_observed_rows <- function(fixture, case_id) {
  data.frame(
    case_id = case_id,
    time_index = seq_along(fixture$y),
    y = fixture$y,
    mu = fixture$mu,
    sigma = fixture$sigma,
    innovation = fixture$innovation,
    innovation_raw = fixture$innovation_raw,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_ts_design_rows <- function(fixture, case_id) {
  data.frame(case_id = case_id, time_index = seq_len(nrow(fixture$Z)), fixture$Z, check.names = FALSE)
}

app_joint_qvp_ts_true_quantile_rows <- function(fixture, case_id) {
  do.call(rbind, lapply(seq_along(fixture$tau), function(k) {
    data.frame(
      case_id = case_id,
      time_index = seq_len(nrow(fixture$true_q)),
      quantile_index = k,
      tau = fixture$tau[[k]],
      true_quantile = fixture$true_q[, k],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qvp_ts_readout_rows <- function(fixture, case_id, fit_label = "truth", alpha = fixture$alpha, beta = fixture$beta) {
  rows <- list()
  for (k in seq_along(fixture$tau)) {
    rows[[length(rows) + 1L]] <- data.frame(
      case_id = case_id,
      fit = fit_label,
      parameter = "alpha",
      feature = "intercept",
      quantile_index = k,
      tau = fixture$tau[[k]],
      value = alpha[[k]],
      stringsAsFactors = FALSE
    )
    rows[[length(rows) + 1L]] <- data.frame(
      case_id = case_id,
      fit = fit_label,
      parameter = "beta",
      feature = rownames(fixture$beta),
      quantile_index = k,
      tau = fixture$tau[[k]],
      value = beta[, k],
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_run_ts_synthetic_suite <- function(
  out_dir,
  scenarios = NULL
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_ts_synthetic_scenarios()
  observed_rows <- list()
  design_rows <- list()
  quantile_rows <- list()
  readout_rows <- list()
  dgp_rows <- list()
  crossing_rows <- list()
  summary_rows <- list()
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, , drop = FALSE]
    case_id <- as.character(sc$case_id[[1L]])
    fixture <- app_joint_qvp_ts_fixture_from_scenario(sc)
    observed_rows[[length(observed_rows) + 1L]] <- app_joint_qvp_ts_observed_rows(fixture, case_id)
    design_rows[[length(design_rows) + 1L]] <- app_joint_qvp_ts_design_rows(fixture, case_id)
    quantile_rows[[length(quantile_rows) + 1L]] <- app_joint_qvp_ts_true_quantile_rows(fixture, case_id)
    readout_rows[[length(readout_rows) + 1L]] <- app_joint_qvp_ts_readout_rows(fixture, case_id)
    dgp_rows[[length(dgp_rows) + 1L]] <- rbind(
      data.frame(case_id = case_id, block = "scalar", name = "Tn", value = length(fixture$y), stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "scalar", name = "df", value = fixture$df, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "scalar", name = "al_tau", value = fixture$al_tau, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "scalar", name = "period", value = fixture$period, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "scalar", name = "location_intercept", value = fixture$location_intercept, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "scalar", name = "scale_intercept", value = fixture$scale_intercept, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "beta_location", name = names(fixture$beta_location), value = fixture$beta_location, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "beta_scale", name = names(fixture$beta_scale), value = fixture$beta_scale, stringsAsFactors = FALSE),
      data.frame(case_id = case_id, block = "q_standardized", name = paste0("tau_", fixture$tau), value = fixture$q_standardized, stringsAsFactors = FALSE)
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stringsAsFactors = FALSE),
      fixture$crossing_diagnostics
    )
    summary_rows[[length(summary_rows) + 1L]] <- data.frame(
      case_id = case_id,
      dynamic = fixture$dynamic,
      likelihood = fixture$likelihood,
      seed = as.integer(sc$seed[[1L]]),
      Tn = length(fixture$y),
      p = ncol(fixture$Z),
      K = length(fixture$tau),
      tau = paste(fixture$tau, collapse = ","),
      sigma_min = min(fixture$sigma),
      sigma_max = max(fixture$sigma),
      y_mean = mean(fixture$y),
      y_sd = stats::sd(fixture$y),
      total_crossing_pairs = sum(fixture$crossing_diagnostics$n_crossing_pairs),
      max_quantile_width = max(fixture$true_q[, ncol(fixture$true_q)] - fixture$true_q[, 1L]),
      notes = as.character(sc$notes[[1L]]),
      stringsAsFactors = FALSE
    )
  }
  paths <- c(
    run_config = app_joint_qvp_write_csv(scenarios, file.path(out_dir, "run_config.csv")),
    scenario_summary = app_joint_qvp_write_csv(do.call(rbind, summary_rows), file.path(out_dir, "scenario_summary.csv")),
    observed_series = app_joint_qvp_write_csv(do.call(rbind, observed_rows), file.path(out_dir, "observed_series.csv")),
    design_matrix = app_joint_qvp_write_csv(do.call(rbind, design_rows), file.path(out_dir, "design_matrix.csv")),
    true_quantile_long = app_joint_qvp_write_csv(do.call(rbind, quantile_rows), file.path(out_dir, "true_quantile_long.csv")),
    true_readout_parameters = app_joint_qvp_write_csv(do.call(rbind, readout_rows), file.path(out_dir, "true_readout_parameters.csv")),
    dgp_parameters = app_joint_qvp_write_csv(do.call(rbind, dgp_rows), file.path(out_dir, "dgp_parameters.csv")),
    crossing_summary = app_joint_qvp_write_csv(do.call(rbind, crossing_rows), file.path(out_dir, "crossing_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_default_synthetic_dgp_registry_path <- function() {
  app_path("application/config/joint_qvp_synthetic_dgp_registry_phase1.csv")
}

app_joint_qvp_synthetic_dgp_registry_columns <- function() {
  c(
    "registry_version", "enabled", "scenario_id", "scenario_class",
    "distribution_family", "dynamics_class", "tau_grid",
    "simulated_length", "washout_length", "train_length", "test_length",
    "seed", "truth_quantile_method", "df", "al_tau", "mixture_weight",
    "mixture_mean_1", "mixture_sd_1", "mixture_mean_2", "mixture_sd_2",
    "period", "initial_y", "location_intercept", "scale_intercept",
    "beta_location", "beta_scale", "regime_start_fraction",
    "regime_location_shift", "regime_scale_shift", "nonlinear_strength",
    "notes"
  )
}

app_joint_qvp_allowed_synthetic_dgp_distributions <- function() {
  c("gaussian", "laplace", "student_t", "asymmetric_laplace", "gaussian_mixture")
}

app_joint_qvp_allowed_synthetic_dgp_dynamics <- function() {
  c(
    "ar1_seasonal_location_scale",
    "heteroskedastic_seasonal",
    "regime_shift_location_scale",
    "nonlinear_reservoir_friendly"
  )
}

app_joint_qvp_registry_feature_names <- function(dynamics_class) {
  dynamics_class <- as.character(dynamics_class)[[1L]]
  base <- c("lag_y", "trend", "sin_season", "cos_season", "abs_lag_scaled")
  if (identical(dynamics_class, "regime_shift_location_scale")) {
    return(c(base, "regime", "post_regime_trend"))
  }
  if (identical(dynamics_class, "nonlinear_reservoir_friendly")) {
    return(c(base, "lag_y_sq_scaled", "sin_lag", "season_lag_interaction"))
  }
  base
}

app_joint_qvp_registry_default_beta <- function(dynamics_class) {
  feature_names <- app_joint_qvp_registry_feature_names(dynamics_class)
  out <- rep(0, length(feature_names))
  names(out) <- feature_names
  out
}

app_joint_qvp_validate_synthetic_dgp_registry <- function(registry) {
  app_check_required_columns(
    registry,
    app_joint_qvp_synthetic_dgp_registry_columns(),
    "joint-QVP synthetic DGP registry"
  )
  if (!nrow(registry)) stop("Synthetic DGP registry must contain at least one row.", call. = FALSE)
  registry$scenario_id <- as.character(registry$scenario_id)
  if (any(!nzchar(registry$scenario_id)) || anyDuplicated(registry$scenario_id)) {
    stop("Synthetic DGP registry scenario_id values must be nonempty and unique.", call. = FALSE)
  }
  if (!all(tolower(as.character(registry$scenario_class)) %in% c("bridge", "stress"))) {
    stop("Synthetic DGP registry scenario_class must be bridge or stress.", call. = FALSE)
  }
  if (!all(as.character(registry$distribution_family) %in% app_joint_qvp_allowed_synthetic_dgp_distributions())) {
    stop("Synthetic DGP registry has unsupported distribution_family values.", call. = FALSE)
  }
  if (!all(as.character(registry$dynamics_class) %in% app_joint_qvp_allowed_synthetic_dgp_dynamics())) {
    stop("Synthetic DGP registry has unsupported dynamics_class values.", call. = FALSE)
  }

  for (ii in seq_len(nrow(registry))) {
    sc <- registry[ii, , drop = FALSE]
    scenario_id <- as.character(sc$scenario_id[[1L]])
    tau <- app_joint_qvp_parse_tau_spec(sc$tau_grid[[1L]], default = c(0.05, 0.5, 0.95))
    simulated_length <- as.integer(sc$simulated_length[[1L]])
    washout_length <- as.integer(sc$washout_length[[1L]])
    train_length <- as.integer(sc$train_length[[1L]])
    test_length <- as.integer(sc$test_length[[1L]])
    seed <- as.integer(sc$seed[[1L]])
    if (any(is.na(c(simulated_length, washout_length, train_length, test_length, seed)))) {
      stop(sprintf("Scenario '%s' has non-finite length or seed fields.", scenario_id), call. = FALSE)
    }
    if (simulated_length < 10L || washout_length < 0L || train_length <= 0L || test_length <= 0L) {
      stop(sprintf("Scenario '%s' has invalid split lengths.", scenario_id), call. = FALSE)
    }
    if (simulated_length != washout_length + train_length + test_length) {
      stop(sprintf("Scenario '%s' simulated_length must equal washout + train + test.", scenario_id), call. = FALSE)
    }
    if (length(tau) < 2L) {
      stop(sprintf("Scenario '%s' must contain at least two quantile levels.", scenario_id), call. = FALSE)
    }
    distribution_family <- as.character(sc$distribution_family[[1L]])
    truth_method <- as.character(sc$truth_quantile_method[[1L]])
    expected_method <- if (identical(distribution_family, "gaussian_mixture")) "numerical" else "analytic"
    if (!identical(truth_method, expected_method)) {
      stop(sprintf("Scenario '%s' truth_quantile_method must be '%s'.", scenario_id, expected_method), call. = FALSE)
    }
    if (identical(distribution_family, "student_t")) {
      df <- as.numeric(sc$df[[1L]])
      if (!is.finite(df) || df <= 2) {
        stop(sprintf("Scenario '%s' requires df > 2.", scenario_id), call. = FALSE)
      }
    }
    if (identical(distribution_family, "asymmetric_laplace")) {
      al_tau <- as.numeric(sc$al_tau[[1L]])
      if (!is.finite(al_tau) || al_tau <= 0 || al_tau >= 1) {
        stop(sprintf("Scenario '%s' requires al_tau in (0, 1).", scenario_id), call. = FALSE)
      }
    }
    if (identical(distribution_family, "gaussian_mixture")) {
      mix <- app_joint_qvp_registry_mixture_params(sc)
      if (!is.finite(mix$weight) || mix$weight <= 0 || mix$weight >= 1 ||
          !is.finite(mix$sd1) || mix$sd1 <= 0 ||
          !is.finite(mix$sd2) || mix$sd2 <= 0) {
        stop(sprintf("Scenario '%s' has invalid Gaussian-mixture parameters.", scenario_id), call. = FALSE)
      }
    }
    period <- as.integer(sc$period[[1L]])
    if (is.na(period) || period < 2L) {
      stop(sprintf("Scenario '%s' requires period >= 2.", scenario_id), call. = FALSE)
    }
    finite_scalars <- c(
      as.numeric(sc$initial_y[[1L]]),
      as.numeric(sc$location_intercept[[1L]]),
      as.numeric(sc$scale_intercept[[1L]]),
      as.numeric(sc$regime_start_fraction[[1L]]),
      as.numeric(sc$nonlinear_strength[[1L]])
    )
    if (any(!is.finite(finite_scalars))) {
      stop(sprintf("Scenario '%s' has non-finite scalar DGP parameters.", scenario_id), call. = FALSE)
    }
    regime_start_fraction <- as.numeric(sc$regime_start_fraction[[1L]])
    if (regime_start_fraction <= 0 || regime_start_fraction >= 1) {
      stop(sprintf("Scenario '%s' requires regime_start_fraction in (0, 1).", scenario_id), call. = FALSE)
    }
    feature_default <- app_joint_qvp_registry_default_beta(sc$dynamics_class[[1L]])
    app_joint_qvp_parse_named_numeric_spec(sc$beta_location[[1L]], feature_default)
    app_joint_qvp_parse_named_numeric_spec(sc$beta_scale[[1L]], feature_default)
  }
  invisible(registry)
}

app_joint_qvp_load_synthetic_dgp_registry <- function(
  path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  enabled_only = TRUE
) {
  registry <- app_read_csv(path)
  app_joint_qvp_validate_synthetic_dgp_registry(registry)
  if (isTRUE(enabled_only) && "enabled" %in% names(registry)) {
    registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
  }
  rownames(registry) <- NULL
  registry
}

app_joint_qvp_laplace_quantile <- function(u) {
  u <- as.numeric(u)
  if (any(!is.finite(u)) || any(u <= 0 | u >= 1)) {
    stop("Laplace quantiles require probabilities in (0, 1).", call. = FALSE)
  }
  ifelse(u < 0.5, log(2 * u), -log(2 * (1 - u)))
}

app_joint_qvp_laplace_random <- function(n) {
  app_joint_qvp_laplace_quantile(stats::runif(as.integer(n)))
}

app_joint_qvp_registry_mixture_params <- function(sc) {
  list(
    weight = as.numeric(sc$mixture_weight[[1L]]),
    mean1 = as.numeric(sc$mixture_mean_1[[1L]]),
    sd1 = as.numeric(sc$mixture_sd_1[[1L]]),
    mean2 = as.numeric(sc$mixture_mean_2[[1L]]),
    sd2 = as.numeric(sc$mixture_sd_2[[1L]])
  )
}

app_joint_qvp_gaussian_mixture_moments <- function(weight, mean1, sd1, mean2, sd2) {
  mean <- weight * mean1 + (1 - weight) * mean2
  variance <- weight * (sd1^2 + (mean1 - mean)^2) +
    (1 - weight) * (sd2^2 + (mean2 - mean)^2)
  list(mean = mean, sd = sqrt(variance))
}

app_joint_qvp_gaussian_mixture_cdf <- function(x, weight, mean1, sd1, mean2, sd2) {
  weight * stats::pnorm(x, mean = mean1, sd = sd1) +
    (1 - weight) * stats::pnorm(x, mean = mean2, sd = sd2)
}

app_joint_qvp_gaussian_mixture_quantile <- function(p, weight, mean1, sd1, mean2, sd2) {
  p <- as.numeric(p)
  if (any(!is.finite(p)) || any(p <= 0 | p >= 1)) {
    stop("Gaussian-mixture quantiles require probabilities in (0, 1).", call. = FALSE)
  }
  lower <- min(mean1 - 14 * sd1, mean2 - 14 * sd2)
  upper <- max(mean1 + 14 * sd1, mean2 + 14 * sd2)
  vapply(p, function(prob) {
    stats::uniroot(
      function(x) app_joint_qvp_gaussian_mixture_cdf(x, weight, mean1, sd1, mean2, sd2) - prob,
      lower = lower,
      upper = upper,
      tol = 1.0e-11
    )$root
  }, numeric(1L))
}

app_joint_qvp_gaussian_mixture_random <- function(n, weight, mean1, sd1, mean2, sd2) {
  n <- as.integer(n)
  z <- stats::runif(n) <= weight
  out <- numeric(n)
  out[z] <- stats::rnorm(sum(z), mean = mean1, sd = sd1)
  out[!z] <- stats::rnorm(sum(!z), mean = mean2, sd = sd2)
  out
}

app_joint_qvp_registry_standardized_quantile <- function(tau, sc) {
  family <- as.character(sc$distribution_family[[1L]])
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (identical(family, "gaussian")) {
    return(stats::qnorm(tau))
  }
  if (identical(family, "laplace")) {
    return(app_joint_qvp_laplace_quantile(tau) / sqrt(2))
  }
  if (identical(family, "student_t")) {
    df <- as.numeric(sc$df[[1L]])
    return(stats::qt(tau, df = df) / sqrt(df / (df - 2)))
  }
  if (identical(family, "asymmetric_laplace")) {
    al_tau <- as.numeric(sc$al_tau[[1L]])
    return(app_joint_qvp_qal(tau, p = al_tau) / app_joint_qvp_al_sd(al_tau))
  }
  if (identical(family, "gaussian_mixture")) {
    mix <- app_joint_qvp_registry_mixture_params(sc)
    moments <- app_joint_qvp_gaussian_mixture_moments(mix$weight, mix$mean1, mix$sd1, mix$mean2, mix$sd2)
    raw_q <- app_joint_qvp_gaussian_mixture_quantile(
      tau,
      weight = mix$weight,
      mean1 = mix$mean1,
      sd1 = mix$sd1,
      mean2 = mix$mean2,
      sd2 = mix$sd2
    )
    return((raw_q - moments$mean) / moments$sd)
  }
  stop(sprintf("Unsupported distribution family '%s'.", family), call. = FALSE)
}

app_joint_qvp_registry_standardized_innovation <- function(n, sc) {
  family <- as.character(sc$distribution_family[[1L]])
  n <- as.integer(n)
  if (identical(family, "gaussian")) {
    raw <- stats::rnorm(n)
    return(list(raw = raw, standardized = raw, center = 0, scale = 1))
  }
  if (identical(family, "laplace")) {
    raw <- app_joint_qvp_laplace_random(n)
    return(list(raw = raw, standardized = raw / sqrt(2), center = 0, scale = sqrt(2)))
  }
  if (identical(family, "student_t")) {
    df <- as.numeric(sc$df[[1L]])
    raw <- stats::rt(n, df = df)
    scale <- sqrt(df / (df - 2))
    return(list(raw = raw, standardized = raw / scale, center = 0, scale = scale))
  }
  if (identical(family, "asymmetric_laplace")) {
    al_tau <- as.numeric(sc$al_tau[[1L]])
    raw <- app_joint_qvp_qal(stats::runif(n), p = al_tau)
    scale <- app_joint_qvp_al_sd(al_tau)
    return(list(raw = raw, standardized = raw / scale, center = 0, scale = scale))
  }
  if (identical(family, "gaussian_mixture")) {
    mix <- app_joint_qvp_registry_mixture_params(sc)
    raw <- app_joint_qvp_gaussian_mixture_random(
      n,
      weight = mix$weight,
      mean1 = mix$mean1,
      sd1 = mix$sd1,
      mean2 = mix$mean2,
      sd2 = mix$sd2
    )
    moments <- app_joint_qvp_gaussian_mixture_moments(mix$weight, mix$mean1, mix$sd1, mix$mean2, mix$sd2)
    return(list(raw = raw, standardized = (raw - moments$mean) / moments$sd, center = moments$mean, scale = moments$sd))
  }
  stop(sprintf("Unsupported distribution family '%s'.", family), call. = FALSE)
}

app_joint_qvp_registry_feature_row <- function(tt, y, simulated_length, sc, feature_names) {
  lag_y <- if (tt == 1L) as.numeric(sc$initial_y[[1L]]) else y[[tt - 1L]]
  period <- as.integer(sc$period[[1L]])
  angle <- 2 * pi * (tt - 1L) / period
  trend <- if (simulated_length > 1L) -1 + 2 * (tt - 1L) / (simulated_length - 1L) else 0
  regime_start <- max(1L, min(simulated_length, floor(as.numeric(sc$regime_start_fraction[[1L]]) * simulated_length)))
  regime <- as.numeric(tt > regime_start)
  post_regime_trend <- if (tt > regime_start) (tt - regime_start) / max(1L, simulated_length - regime_start) else 0
  base <- c(
    lag_y = lag_y,
    trend = trend,
    sin_season = sin(angle),
    cos_season = cos(angle),
    abs_lag_scaled = abs(lag_y) / (1 + abs(lag_y)),
    regime = regime,
    post_regime_trend = post_regime_trend,
    lag_y_sq_scaled = lag_y^2 / (1 + lag_y^2),
    sin_lag = sin(lag_y),
    season_lag_interaction = sin(angle) * lag_y / (1 + abs(lag_y))
  )
  out <- as.numeric(base[feature_names])
  names(out) <- feature_names
  out
}

app_joint_qvp_registry_split_labels <- function(simulated_length, washout_length, train_length, test_length) {
  time_index <- seq_len(simulated_length)
  train_end <- washout_length + train_length
  split <- ifelse(time_index <= washout_length, "washout", ifelse(time_index <= train_end, "train", "test"))
  split_index <- ave(time_index, split, FUN = seq_along)
  retained_time_index <- ifelse(split == "washout", NA_integer_, time_index - washout_length)
  data.frame(
    time_index = time_index,
    split = split,
    split_index = as.integer(split_index),
    retained_time_index = as.integer(retained_time_index),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_fixture_from_synthetic_dgp_registry_row <- function(sc) {
  app_joint_qvp_validate_synthetic_dgp_registry(sc)
  scenario_id <- as.character(sc$scenario_id[[1L]])
  simulated_length <- as.integer(sc$simulated_length[[1L]])
  washout_length <- as.integer(sc$washout_length[[1L]])
  train_length <- as.integer(sc$train_length[[1L]])
  test_length <- as.integer(sc$test_length[[1L]])
  tau <- app_joint_qvp_parse_tau_spec(sc$tau_grid[[1L]], default = c(0.05, 0.5, 0.95))
  feature_names <- app_joint_qvp_registry_feature_names(sc$dynamics_class[[1L]])
  beta_default <- app_joint_qvp_registry_default_beta(sc$dynamics_class[[1L]])
  beta_location <- app_joint_qvp_parse_named_numeric_spec(sc$beta_location[[1L]], beta_default)
  beta_scale <- app_joint_qvp_parse_named_numeric_spec(sc$beta_scale[[1L]], beta_default)

  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", envir = .GlobalEnv)
  } else {
    NULL
  }
  on.exit({
    if (is.null(old_seed)) {
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(sc$seed[[1L]]))

  innovations <- app_joint_qvp_registry_standardized_innovation(simulated_length, sc)
  q_standardized <- app_joint_qvp_registry_standardized_quantile(tau, sc)
  y <- mu <- sigma <- numeric(simulated_length)
  Z <- matrix(NA_real_, nrow = simulated_length, ncol = length(feature_names), dimnames = list(NULL, feature_names))
  for (tt in seq_len(simulated_length)) {
    z_t <- app_joint_qvp_registry_feature_row(tt, y, simulated_length, sc, feature_names)
    Z[tt, ] <- z_t
    mu[[tt]] <- as.numeric(sc$location_intercept[[1L]]) + sum(beta_location * z_t)
    sigma[[tt]] <- as.numeric(sc$scale_intercept[[1L]]) + sum(beta_scale * z_t)
    if (!is.finite(sigma[[tt]]) || sigma[[tt]] <= 0) {
      stop(sprintf("Scenario '%s' scale became non-positive at time %s.", scenario_id, tt), call. = FALSE)
    }
    y[[tt]] <- mu[[tt]] + sigma[[tt]] * innovations$standardized[[tt]]
  }
  K <- length(tau)
  alpha <- as.numeric(sc$location_intercept[[1L]]) + as.numeric(sc$scale_intercept[[1L]]) * q_standardized
  beta <- matrix(rep(beta_location, K), nrow = length(feature_names), ncol = K, dimnames = list(feature_names, paste0("tau_", tau))) +
    beta_scale %o% q_standardized
  true_q <- Z %*% beta + matrix(alpha, nrow = simulated_length, ncol = K, byrow = TRUE)
  colnames(true_q) <- paste0("q_tau_", gsub("[^0-9]+", "p", format(tau, trim = TRUE, scientific = FALSE)))
  split <- app_joint_qvp_registry_split_labels(simulated_length, washout_length, train_length, test_length)
  list(
    scenario_id = scenario_id,
    scenario_class = as.character(sc$scenario_class[[1L]]),
    distribution_family = as.character(sc$distribution_family[[1L]]),
    dynamics_class = as.character(sc$dynamics_class[[1L]]),
    truth_quantile_method = as.character(sc$truth_quantile_method[[1L]]),
    y = y,
    Z = Z,
    tau = tau,
    alpha = alpha,
    beta = beta,
    true_q = true_q,
    mu = mu,
    sigma = sigma,
    innovation = innovations$standardized,
    innovation_raw = innovations$raw,
    innovation_center = innovations$center,
    innovation_scale = innovations$scale,
    q_standardized = q_standardized,
    split = split,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length,
    seed = as.integer(sc$seed[[1L]]),
    period = as.integer(sc$period[[1L]]),
    initial_y = as.numeric(sc$initial_y[[1L]]),
    location_intercept = as.numeric(sc$location_intercept[[1L]]),
    scale_intercept = as.numeric(sc$scale_intercept[[1L]]),
    beta_location = beta_location,
    beta_scale = beta_scale,
    notes = as.character(sc$notes[[1L]]),
    dynamic = as.character(sc$dynamics_class[[1L]]),
    likelihood = paste0("standardized_", as.character(sc$distribution_family[[1L]])),
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(true_q, tau)
  )
}

app_joint_qvp_registry_observed_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    time_index = seq_along(fixture$y),
    fixture$split,
    y = fixture$y,
    mu = fixture$mu,
    sigma = fixture$sigma,
    innovation = fixture$innovation,
    innovation_raw = fixture$innovation_raw,
    distribution_family = fixture$distribution_family,
    dynamics_class = fixture$dynamics_class,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_registry_design_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    time_index = seq_len(nrow(fixture$Z)),
    fixture$split,
    fixture$Z,
    check.names = FALSE
  )
}

app_joint_qvp_registry_true_quantile_wide_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    time_index = seq_len(nrow(fixture$true_q)),
    fixture$split,
    fixture$true_q,
    check.names = FALSE
  )
}

app_joint_qvp_registry_true_quantile_long_rows <- function(fixture) {
  do.call(rbind, lapply(seq_along(fixture$tau), function(k) {
    data.frame(
      scenario_id = fixture$scenario_id,
      time_index = seq_len(nrow(fixture$true_q)),
      fixture$split,
      quantile_index = k,
      tau = fixture$tau[[k]],
      true_quantile = fixture$true_q[, k],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qvp_registry_split_metadata_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    simulated_length = fixture$simulated_length,
    washout_length = fixture$washout_length,
    train_length = fixture$train_length,
    test_length = fixture$test_length,
    washout_start = if (fixture$washout_length > 0L) 1L else NA_integer_,
    washout_end = if (fixture$washout_length > 0L) fixture$washout_length else NA_integer_,
    train_start = fixture$washout_length + 1L,
    train_end = fixture$washout_length + fixture$train_length,
    test_start = fixture$washout_length + fixture$train_length + 1L,
    test_end = fixture$simulated_length,
    retained_start = fixture$washout_length + 1L,
    retained_end = fixture$simulated_length,
    split_strategy = "contiguous_washout_train_test",
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_registry_dgp_parameter_rows <- function(fixture, sc) {
  scalar_rows <- data.frame(
    scenario_id = fixture$scenario_id,
    block = "scalar",
    name = c(
      "simulated_length", "washout_length", "train_length", "test_length",
      "seed", "period", "initial_y", "location_intercept", "scale_intercept",
      "innovation_center", "innovation_scale"
    ),
    value = as.character(c(
      fixture$simulated_length, fixture$washout_length, fixture$train_length,
      fixture$test_length, fixture$seed, fixture$period, fixture$initial_y,
      fixture$location_intercept, fixture$scale_intercept,
      fixture$innovation_center, fixture$innovation_scale
    )),
    stringsAsFactors = FALSE
  )
  beta_rows <- rbind(
    data.frame(
      scenario_id = fixture$scenario_id,
      block = "beta_location",
      name = names(fixture$beta_location),
      value = as.character(fixture$beta_location),
      stringsAsFactors = FALSE
    ),
    data.frame(
      scenario_id = fixture$scenario_id,
      block = "beta_scale",
      name = names(fixture$beta_scale),
      value = as.character(fixture$beta_scale),
      stringsAsFactors = FALSE
    ),
    data.frame(
      scenario_id = fixture$scenario_id,
      block = "q_standardized",
      name = paste0("tau_", fixture$tau),
      value = as.character(fixture$q_standardized),
      stringsAsFactors = FALSE
    )
  )
  registry_rows <- data.frame(
    scenario_id = fixture$scenario_id,
    block = "registry",
    name = names(sc),
    value = vapply(sc, function(x) as.character(x[[1L]]), character(1L)),
    stringsAsFactors = FALSE
  )
  rbind(scalar_rows, beta_rows, registry_rows)
}

app_joint_qvp_registry_scenario_summary_row <- function(fixture) {
  retained <- fixture$split$split != "washout"
  train <- fixture$split$split == "train"
  test <- fixture$split$split == "test"
  data.frame(
    scenario_id = fixture$scenario_id,
    scenario_class = fixture$scenario_class,
    distribution_family = fixture$distribution_family,
    dynamics_class = fixture$dynamics_class,
    truth_quantile_method = fixture$truth_quantile_method,
    seed = fixture$seed,
    simulated_length = fixture$simulated_length,
    washout_length = fixture$washout_length,
    train_length = fixture$train_length,
    test_length = fixture$test_length,
    p = ncol(fixture$Z),
    K = length(fixture$tau),
    tau_grid = paste(fixture$tau, collapse = ","),
    sigma_min = min(fixture$sigma),
    sigma_max = max(fixture$sigma),
    retained_y_mean = mean(fixture$y[retained]),
    retained_y_sd = stats::sd(fixture$y[retained]),
    train_y_mean = mean(fixture$y[train]),
    test_y_mean = mean(fixture$y[test]),
    total_crossing_pairs = sum(fixture$crossing_diagnostics$n_crossing_pairs),
    max_quantile_width = max(fixture$true_q[, ncol(fixture$true_q)] - fixture$true_q[, 1L]),
    notes = fixture$notes,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_registry_validation_rows <- function(registry, fixtures) {
  rows <- list(data.frame(
    scope = "registry",
    scenario_id = "ALL",
    check = "schema_unique_ids_and_declared_fields",
    status = "pass",
    detail = "registry schema validation passed",
    stringsAsFactors = FALSE
  ))
  for (fixture in fixtures) {
    monotone <- all(apply(fixture$true_q, 1L, function(x) all(diff(x) >= -1.0e-10)))
    split_counts <- table(fixture$split$split)
    split_ok <- identical(as.integer(split_counts[c("washout", "train", "test")]), c(fixture$washout_length, fixture$train_length, fixture$test_length))
    checks <- list(
      finite_observed = all(is.finite(fixture$y)),
      finite_design = all(is.finite(fixture$Z)),
      finite_true_quantiles = all(is.finite(fixture$true_q)),
      positive_scale = all(fixture$sigma > 0),
      monotone_true_quantiles = monotone,
      split_lengths = isTRUE(split_ok),
      zero_true_crossing_pairs = sum(fixture$crossing_diagnostics$n_crossing_pairs) == 0L
    )
    for (nm in names(checks)) {
      rows[[length(rows) + 1L]] <- data.frame(
        scope = "scenario",
        scenario_id = fixture$scenario_id,
        check = nm,
        status = if (isTRUE(checks[[nm]])) "pass" else "fail",
        detail = if (isTRUE(checks[[nm]])) "check passed" else "check failed",
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

app_joint_qvp_registry_readme_lines <- function(registry, scenario_summary) {
  c(
    "# Joint-QVP Synthetic DGP Registry Phase 1",
    "",
    "This artifact directory materializes the versioned Phase 1 synthetic DGP registry.",
    "It contains source fixtures only: observed series, design/features, true conditional quantiles, split metadata, DGP parameters, provenance, and hashes.",
    "",
    "This is not a fit or forecast validation result. It is the reproducible fixture layer for the next validation stage.",
    "",
    sprintf("- Registry rows: %s", nrow(registry)),
    sprintf("- Bridge scenarios: %s", sum(registry$scenario_class == "bridge")),
    sprintf("- Stress scenarios: %s", sum(registry$scenario_class == "stress")),
    sprintf("- Total observed rows: %s", sum(scenario_summary$simulated_length)),
    sprintf("- Quantile grid: %s", scenario_summary$tau_grid[[1L]]),
    "",
    "Primary files:",
    "",
    "- `frozen_registry.csv`: exact registry snapshot used for this materialization.",
    "- `observed_series.csv`: generated response, location, scale, innovations, and split labels.",
    "- `design_matrix.csv`: deterministic feature matrix used by the DGP.",
    "- `true_quantile_wide.csv` and `true_quantile_long.csv`: oracle conditional quantiles.",
    "- `split_metadata.csv`: washout/train/test windows.",
    "- `dgp_parameters.csv`: scalar, beta, quantile, and registry parameters in long format.",
    "- `registry_validation.csv`: pass/fail checks for schema, finiteness, scale, monotonicity, and splits.",
    "- `artifact_manifest.csv`: SHA-256 hashes for reproducibility."
  )
}

app_joint_qvp_materialize_synthetic_dgp_registry <- function(
  out_dir,
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  registry_source <- if (is.null(registry)) {
    app_read_csv(registry_path)
  } else {
    registry
  }
  app_joint_qvp_validate_synthetic_dgp_registry(registry_source)
  registry_source <- registry_source[app_as_bool_vec(registry_source$enabled), , drop = FALSE]
  rownames(registry_source) <- NULL
  fixtures <- lapply(seq_len(nrow(registry_source)), function(ii) {
    app_joint_qvp_fixture_from_synthetic_dgp_registry_row(registry_source[ii, , drop = FALSE])
  })

  observed <- do.call(rbind, lapply(fixtures, app_joint_qvp_registry_observed_rows))
  design <- app_bind_rows_fill(lapply(fixtures, app_joint_qvp_registry_design_rows))
  true_wide <- do.call(rbind, lapply(fixtures, app_joint_qvp_registry_true_quantile_wide_rows))
  true_long <- do.call(rbind, lapply(fixtures, app_joint_qvp_registry_true_quantile_long_rows))
  split_metadata <- do.call(rbind, lapply(fixtures, app_joint_qvp_registry_split_metadata_rows))
  dgp_parameters <- do.call(rbind, Map(app_joint_qvp_registry_dgp_parameter_rows, fixtures, split(registry_source, seq_len(nrow(registry_source)))))
  crossing_summary <- do.call(rbind, lapply(fixtures, function(fixture) {
    cbind(data.frame(scenario_id = fixture$scenario_id, stringsAsFactors = FALSE), fixture$crossing_diagnostics)
  }))
  scenario_summary <- do.call(rbind, lapply(fixtures, app_joint_qvp_registry_scenario_summary_row))
  validation <- app_joint_qvp_registry_validation_rows(registry_source, fixtures)
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_registry_readme_lines(registry_source, scenario_summary), readme_path, useBytes = TRUE)

  paths <- c(
    frozen_registry = app_joint_qvp_write_csv(registry_source, file.path(out_dir, "frozen_registry.csv")),
    registry_validation = app_joint_qvp_write_csv(validation, file.path(out_dir, "registry_validation.csv")),
    scenario_summary = app_joint_qvp_write_csv(scenario_summary, file.path(out_dir, "scenario_summary.csv")),
    observed_series = app_joint_qvp_write_csv(observed, file.path(out_dir, "observed_series.csv")),
    design_matrix = app_joint_qvp_write_csv(design, file.path(out_dir, "design_matrix.csv")),
    true_quantile_wide = app_joint_qvp_write_csv(true_wide, file.path(out_dir, "true_quantile_wide.csv")),
    true_quantile_long = app_joint_qvp_write_csv(true_long, file.path(out_dir, "true_quantile_long.csv")),
    split_metadata = app_joint_qvp_write_csv(split_metadata, file.path(out_dir, "split_metadata.csv")),
    dgp_parameters = app_joint_qvp_write_csv(dgp_parameters, file.path(out_dir, "dgp_parameters.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    registry = registry_source,
    fixtures = fixtures,
    scenario_summary = scenario_summary,
    registry_validation = validation
  )
}

app_joint_qvp_default_synthetic_dgp_fixture_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_registry_phase1_20260702")
}

app_joint_qvp_default_synthetic_dgp_fit_validation_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_fit_validation_phase2_20260702")
}

app_joint_qvp_phase1_fixture_required_files <- function() {
  c(
    "frozen_registry.csv",
    "registry_validation.csv",
    "scenario_summary.csv",
    "observed_series.csv",
    "design_matrix.csv",
    "true_quantile_wide.csv",
    "true_quantile_long.csv",
    "split_metadata.csv",
    "dgp_parameters.csv",
    "crossing_summary.csv",
    "provenance.csv",
    "README.md",
    "artifact_manifest.csv"
  )
}

app_joint_qvp_verify_phase1_fixture_dir <- function(fixture_dir) {
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  required <- app_joint_qvp_phase1_fixture_required_files()
  missing <- required[!file.exists(file.path(fixture_dir, required))]
  if (length(missing)) {
    stop(
      "Phase 1 fixture directory is missing required file(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  manifest <- app_read_csv(file.path(fixture_dir, "artifact_manifest.csv"))
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), "Phase 1 artifact manifest")
  manifest$fixture_dir <- fixture_dir
  manifest$absolute_path <- file.path(fixture_dir, manifest$relative_path)
  manifest$file_exists <- file.exists(manifest$absolute_path)
  manifest$observed_sha256 <- ifelse(
    manifest$file_exists,
    vapply(manifest$absolute_path, app_sha256_file, character(1L)),
    NA_character_
  )
  manifest$hash_verified <- manifest$file_exists & manifest$observed_sha256 == manifest$sha256
  if (any(!manifest$hash_verified)) {
    bad <- manifest$relative_path[!manifest$hash_verified]
    stop("Phase 1 fixture hash verification failed for: ", paste(bad, collapse = ", "), call. = FALSE)
  }
  manifest
}

app_joint_qvp_load_phase1_fixture_tables <- function(fixture_dir) {
  fixture_manifest <- app_joint_qvp_verify_phase1_fixture_dir(fixture_dir)
  fixture_dir <- normalizePath(fixture_dir, mustWork = TRUE)
  tables <- list(
    fixture_dir = fixture_dir,
    fixture_source_manifest = fixture_manifest,
    frozen_registry = app_read_csv(file.path(fixture_dir, "frozen_registry.csv")),
    registry_validation = app_read_csv(file.path(fixture_dir, "registry_validation.csv")),
    scenario_summary = app_read_csv(file.path(fixture_dir, "scenario_summary.csv")),
    observed_series = app_read_csv(file.path(fixture_dir, "observed_series.csv")),
    design_matrix = app_read_csv(file.path(fixture_dir, "design_matrix.csv")),
    true_quantile_wide = app_read_csv(file.path(fixture_dir, "true_quantile_wide.csv")),
    true_quantile_long = app_read_csv(file.path(fixture_dir, "true_quantile_long.csv")),
    split_metadata = app_read_csv(file.path(fixture_dir, "split_metadata.csv")),
    dgp_parameters = app_read_csv(file.path(fixture_dir, "dgp_parameters.csv")),
    crossing_summary = app_read_csv(file.path(fixture_dir, "crossing_summary.csv"))
  )
  app_check_required_columns(tables$observed_series, c("scenario_id", "time_index", "split", "y", "sigma"), "Phase 1 observed_series")
  app_check_required_columns(tables$design_matrix, c("scenario_id", "time_index", "split"), "Phase 1 design_matrix")
  app_check_required_columns(tables$true_quantile_wide, c("scenario_id", "time_index", "split"), "Phase 1 true_quantile_wide")
  app_check_required_columns(tables$true_quantile_long, c("scenario_id", "time_index", "split", "quantile_index", "tau", "true_quantile"), "Phase 1 true_quantile_long")
  app_check_required_columns(tables$split_metadata, c("scenario_id", "washout_length", "train_length", "test_length", "train_start", "train_end"), "Phase 1 split_metadata")
  tables
}

app_joint_qvp_phase2_feature_columns <- function(design_block) {
  meta <- c("scenario_id", "time_index", "split", "split_index", "retained_time_index")
  candidates <- setdiff(names(design_block), meta)
  keep <- vapply(candidates, function(nm) any(is.finite(as.numeric(design_block[[nm]]))), logical(1L))
  candidates[keep]
}

app_joint_qvp_phase2_train_fixture_from_tables <- function(tables, scenario_id) {
  scenario_id <- as.character(scenario_id)
  observed <- tables$observed_series[tables$observed_series$scenario_id == scenario_id, , drop = FALSE]
  design <- tables$design_matrix[tables$design_matrix$scenario_id == scenario_id, , drop = FALSE]
  truth <- tables$true_quantile_wide[tables$true_quantile_wide$scenario_id == scenario_id, , drop = FALSE]
  split_meta <- tables$split_metadata[tables$split_metadata$scenario_id == scenario_id, , drop = FALSE]
  summary <- tables$scenario_summary[tables$scenario_summary$scenario_id == scenario_id, , drop = FALSE]
  registry <- tables$frozen_registry[tables$frozen_registry$scenario_id == scenario_id, , drop = FALSE]
  if (!nrow(observed) || !nrow(design) || !nrow(truth) || nrow(split_meta) != 1L || nrow(summary) != 1L) {
    stop(sprintf("Phase 1 fixture tables are incomplete for scenario '%s'.", scenario_id), call. = FALSE)
  }
  train_obs <- observed[observed$split == "train", , drop = FALSE]
  train_design <- design[design$split == "train", , drop = FALSE]
  train_truth <- truth[truth$split == "train", , drop = FALSE]
  if (!nrow(train_obs) || nrow(train_obs) != nrow(train_design) || nrow(train_obs) != nrow(train_truth)) {
    stop(sprintf("Train split row counts are malformed for scenario '%s'.", scenario_id), call. = FALSE)
  }
  if (any(train_obs$time_index < split_meta$train_start[[1L]] | train_obs$time_index > split_meta$train_end[[1L]])) {
    stop(sprintf("Train split leakage check failed for scenario '%s'.", scenario_id), call. = FALSE)
  }
  if (any(observed$split == "test" & observed$time_index %in% train_obs$time_index)) {
    stop(sprintf("Test observations leaked into train split for scenario '%s'.", scenario_id), call. = FALSE)
  }

  feature_cols <- app_joint_qvp_phase2_feature_columns(train_design)
  if (!length(feature_cols)) stop(sprintf("No finite feature columns found for scenario '%s'.", scenario_id), call. = FALSE)
  Z <- as.matrix(train_design[, feature_cols, drop = FALSE])
  storage.mode(Z) <- "double"
  q_cols <- grep("^q_tau_", names(train_truth), value = TRUE)
  if (!length(q_cols)) stop(sprintf("No true quantile columns found for scenario '%s'.", scenario_id), call. = FALSE)
  tau <- app_joint_qvp_parse_tau_spec(summary$tau_grid[[1L]])
  if (length(q_cols) != length(tau)) {
    stop(sprintf("Tau grid and true quantile columns do not match for scenario '%s'.", scenario_id), call. = FALSE)
  }
  true_q <- as.matrix(train_truth[, q_cols, drop = FALSE])
  storage.mode(true_q) <- "double"
  colnames(true_q) <- q_cols
  y <- as.numeric(train_obs$y)
  sigma <- as.numeric(train_obs$sigma)
  if (any(!is.finite(y)) || any(!is.finite(Z)) || any(!is.finite(true_q)) || any(!is.finite(sigma)) || any(sigma <= 0)) {
    stop(sprintf("Non-finite train fixture values found for scenario '%s'.", scenario_id), call. = FALSE)
  }
  crossing <- app_joint_qvp_crossing_diagnostics(true_q, tau)
  list(
    scenario_id = scenario_id,
    case_id = scenario_id,
    scenario_class = summary$scenario_class[[1L]],
    distribution_family = summary$distribution_family[[1L]],
    dynamics_class = summary$dynamics_class[[1L]],
    truth_quantile_method = summary$truth_quantile_method[[1L]],
    y = y,
    Z = Z,
    tau = tau,
    true_q = true_q,
    sigma = sigma,
    time_index = train_obs$time_index,
    split = train_obs$split,
    simulated_length = split_meta$simulated_length[[1L]],
    washout_length = split_meta$washout_length[[1L]],
    train_length = split_meta$train_length[[1L]],
    test_length = split_meta$test_length[[1L]],
    train_start = split_meta$train_start[[1L]],
    train_end = split_meta$train_end[[1L]],
    seed = if (nrow(registry)) as.integer(registry$seed[[1L]]) else as.integer(summary$seed[[1L]]),
    dynamic = summary$dynamics_class[[1L]],
    likelihood = paste0("standardized_", summary$distribution_family[[1L]]),
    notes = summary$notes[[1L]],
    crossing_diagnostics = crossing
  )
}

app_joint_qvp_phase2_pinball_rows <- function(fixture, qhat, fit_label) {
  qhat <- as.matrix(qhat)
  rows <- lapply(seq_along(fixture$tau), function(k) {
    e <- fixture$y - qhat[, k]
    data.frame(
      scenario_id = fixture$scenario_id,
      fit = fit_label,
      quantile_index = k,
      tau = fixture$tau[[k]],
      pinball_mean = mean(ifelse(e >= 0, fixture$tau[[k]] * e, (fixture$tau[[k]] - 1) * e)),
      pinball_sum = sum(ifelse(e >= 0, fixture$tau[[k]] * e, (fixture$tau[[k]] - 1) * e)),
      n_train = length(fixture$y),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_phase2_empty_mcmc_reference_summary <- function() {
  data.frame(
    scenario_id = character(),
    reference_requested = logical(),
    reference_status = character(),
    init_source = character(),
    n_chains = integer(),
    n_keep_total = integer(),
    max_normalized_distance = numeric(),
    max_chain_to_pooled_normalized_distance = numeric(),
    all_draws_finite = logical(),
    note = character(),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase2_empty_mcmc_draw_summary <- function() {
  data.frame(
    chain_id = integer(),
    chain_seed = integer(),
    case_id = character(),
    stress_case = character(),
    scenario = character(),
    block = character(),
    n_draws = integer(),
    n_parameters = integer(),
    all_finite = logical(),
    mean_abs_draw_mean = numeric(),
    mean_draw_sd = numeric(),
    min_value = numeric(),
    max_value = numeric(),
    lower_bound = numeric(),
    upper_bound = numeric(),
    lower_bound_hit_fraction = numeric(),
    upper_bound_hit_fraction = numeric(),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase2_empty_vb_mcmc_distance_summary <- function() {
  data.frame(
    case_id = character(),
    stress_case = character(),
    scenario = character(),
    beta_l2_to_mcmc = numeric(),
    alpha_l2_to_mcmc = numeric(),
    sigma_l2_to_mcmc = numeric(),
    qhat_l2_to_mcmc = numeric(),
    beta_normalized_distance = numeric(),
    alpha_normalized_distance = numeric(),
    sigma_normalized_distance = numeric(),
    qhat_normalized_distance = numeric(),
    max_normalized_distance = numeric(),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase2_empty_chain_summary <- function() {
  data.frame(
    case_id = character(),
    stress_case = character(),
    scenario = character(),
    chain_id = integer(),
    beta_l2_to_pooled = numeric(),
    alpha_l2_to_pooled = numeric(),
    sigma_l2_to_pooled = numeric(),
    qhat_l2_to_pooled = numeric(),
    beta_normalized_to_pooled = numeric(),
    alpha_normalized_to_pooled = numeric(),
    sigma_normalized_to_pooled = numeric(),
    qhat_normalized_to_pooled = numeric(),
    max_normalized_to_pooled = numeric(),
    chain_seed = integer(),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase2_assessment_rows <- function(
  fit_summary,
  truth_fit_summary,
  mcmc_reference_summary,
  source_hashes_verified = TRUE,
  vb_truth_pass = 1.5,
  vb_mcmc_pass = 5,
  hit_rate_floor = 0.10,
  hit_rate_multiplier = 2.5
) {
  scenarios <- unique(fit_summary$scenario_id)
  rows <- vector("list", length(scenarios))
  for (ii in seq_along(scenarios)) {
    scenario_id <- scenarios[[ii]]
    vb <- fit_summary[fit_summary$scenario_id == scenario_id & fit_summary$fit == "vb", , drop = FALSE]
    mref <- mcmc_reference_summary[mcmc_reference_summary$scenario_id == scenario_id, , drop = FALSE]
    truth_block <- truth_fit_summary[truth_fit_summary$scenario_id == scenario_id & truth_fit_summary$fit == "vb", , drop = FALSE]
    tau <- truth_block$tau
    hit_allowed <- pmax(hit_rate_floor, hit_rate_multiplier * sqrt(tau * (1 - tau) / vb$n_train[[1L]]))
    hit_error <- abs(truth_block$hit_rate_minus_tau)
    finite_required <- nrow(vb) == 1L &&
      isTRUE(source_hashes_verified) &&
      all(is.finite(c(
        vb$truth_normalized_qhat_distance,
        vb$max_abs_hit_rate_error,
        vb$total_crossing_pairs,
        vb$pinball_mean_mean
      ))) &&
      all(is.finite(truth_block$rmse_to_truth)) &&
      all(is.finite(truth_block$empirical_hit_rate))
    implementation_fail <- !finite_required ||
      !isTRUE(vb$no_test_leakage[[1L]]) ||
      vb$total_crossing_pairs[[1L]] > 0
    implementation_status <- if (implementation_fail) {
      "fail"
    } else if (!isTRUE(vb$converged[[1L]]) || !identical(vb$status[[1L]], "prototype_success")) {
      "review"
    } else {
      "pass"
    }
    truth_distance_status <- if (is.finite(vb$truth_normalized_qhat_distance[[1L]]) &&
        vb$truth_normalized_qhat_distance[[1L]] <= vb_truth_pass) {
      "pass"
    } else {
      "review"
    }
    hit_rate_status <- if (length(hit_error) && all(hit_error <= hit_allowed, na.rm = FALSE)) "pass" else "review"
    objective_status <- if (identical(vb$objective_status[[1L]], "pass")) "pass" else "review"
    mcmc_status <- "skipped"
    if (nrow(mref) && isTRUE(mref$reference_requested[[1L]])) {
      if (identical(mref$reference_status[[1L]], "fail")) {
        mcmc_status <- "fail"
      } else if (is.finite(mref$max_normalized_distance[[1L]]) &&
          mref$max_normalized_distance[[1L]] <= vb_mcmc_pass &&
          isTRUE(mref$all_draws_finite[[1L]]) &&
          identical(mref$init_source[[1L]], "provided")) {
        mcmc_status <- "pass"
      } else {
        mcmc_status <- "review"
      }
    }
    gate_status <- if (implementation_status == "fail" || mcmc_status == "fail") {
      "fail"
    } else if (any(c(implementation_status, truth_distance_status, hit_rate_status, objective_status, mcmc_status) == "review")) {
      "review"
    } else {
      "pass"
    }
    reasons <- c(
      if (!isTRUE(source_hashes_verified)) "fixture source hash failure",
      if (!finite_required) "non-finite required fit metrics",
      if (!isTRUE(vb$no_test_leakage[[1L]])) "train/test leakage",
      if (vb$total_crossing_pairs[[1L]] > 0) "fitted quantile crossings",
      if (!identical(implementation_status, "pass") && !identical(implementation_status, "fail")) "VB convergence review",
      if (!identical(truth_distance_status, "pass")) "truth-distance review",
      if (!identical(hit_rate_status, "pass")) "hit-rate review",
      if (!identical(objective_status, "pass")) "objective review",
      if (identical(mcmc_status, "review")) "selected short MCMC reference review"
    )
    rows[[ii]] <- data.frame(
      scenario_id = scenario_id,
      implementation_status = implementation_status,
      truth_distance_status = truth_distance_status,
      hit_rate_status = hit_rate_status,
      objective_status = objective_status,
      mcmc_reference_status = mcmc_status,
      gate_status = gate_status,
      vb_truth_pass_threshold = vb_truth_pass,
      vb_mcmc_pass_threshold = vb_mcmc_pass,
      max_hit_rate_error = if (length(hit_error)) max(hit_error) else NA_real_,
      max_hit_rate_allowed = if (length(hit_allowed)) max(hit_allowed) else NA_real_,
      note = app_joint_qvp_ts_assessment_note(reasons),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase2_readme_lines <- function(run_config, assessment) {
  status_counts <- table(assessment$gate_status)
  c(
    "# Joint-QVP Synthetic DGP Fit Validation Phase 2",
    "",
    "This artifact directory contains registry-driven train-split fit validation for the joint-QVP synthetic DGP study.",
    "It consumes Phase 1 fixtures, verifies source hashes, fits AL-VB on train rows only, and runs selected short VB-initialized MCMC references.",
    "",
    "This is not rolling-origin forecast validation. Forecast validation is Phase 3.",
    "",
    sprintf("- Scenarios: %s", length(unique(run_config$scenario_id))),
    sprintf("- MCMC reference scenarios: %s", sum(app_as_bool_vec(run_config$mcmc_reference))),
    sprintf("- Gate counts: %s", paste(paste(names(status_counts), as.integer(status_counts), sep = "="), collapse = ", ")),
    "",
    "Primary files:",
    "",
    "- `run_config.csv`: fit controls and scenario metadata.",
    "- `fixture_source_manifest.csv`: verified Phase 1 source hashes.",
    "- `fit_validation_assessment.csv`: pass/review/fail gates.",
    "- `fit_summary.csv`: scenario-level VB and selected MCMC fit summaries.",
    "- `truth_fit_summary.csv`: quantile-path recovery and empirical hit rates.",
    "- `pinball_summary.csv`: train-split check loss summaries.",
    "- `hit_rate_summary.csv`: train-split coverage by tau.",
    "- `mcmc_reference_summary.csv`: selected short MCMC reference status.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 2 artifacts."
  )
}

app_joint_qvp_run_synthetic_dgp_fit_validation <- function(
  out_dir,
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  fixture_dir = NULL,
  registry = NULL,
  scenario_ids = NULL,
  mcmc_reference_scenarios = c("normal_bridge", "gaussian_mixture_bridge", "asymmetric_laplace_tail", "persistent_heavy_tail"),
  kappa = 1,
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 120L,
  adaptive_vb_max_iter_grid = c(vb_max_iter, 240L),
  rhs_vb_inner = 5L,
  n_chains = 2L,
  mcmc_n_iter = 60L,
  mcmc_burn = 30L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 2000L,
  chain_seed_stride = 10000L,
  sigma_upper_multiplier = 50
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(fixture_dir)) {
    fixture_dir <- file.path(out_dir, "phase1_fixtures")
    app_joint_qvp_materialize_synthetic_dgp_registry(
      out_dir = fixture_dir,
      registry_path = registry_path,
      registry = registry
    )
  }
  tables <- app_joint_qvp_load_phase1_fixture_tables(fixture_dir)
  source_hashes_verified <- all(tables$fixture_source_manifest$hash_verified)
  available_scenario_ids <- tables$scenario_summary$scenario_id
  if (!is.null(scenario_ids)) {
    requested_ids <- unique(as.character(scenario_ids))
    requested_ids <- requested_ids[nzchar(requested_ids)]
    missing_ids <- setdiff(requested_ids, available_scenario_ids)
    if (length(missing_ids)) {
      stop("Requested Phase 2 scenario id(s) are not present in the Phase 1 fixtures: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    scenario_ids <- requested_ids
  } else {
    scenario_ids <- available_scenario_ids
  }
  if (!length(scenario_ids)) stop("No Phase 2 scenarios selected.", call. = FALSE)
  fixtures <- lapply(scenario_ids, function(id) app_joint_qvp_phase2_train_fixture_from_tables(tables, id))
  names(fixtures) <- scenario_ids
  mcmc_reference_scenarios <- unique(as.character(mcmc_reference_scenarios))

  fit_rows <- list()
  truth_rows <- list()
  pinball_rows <- list()
  hit_rows <- list()
  crossing_rows <- list()
  vb_audit_rows <- list()
  objective_rows <- list()
  elbo_rows <- list()
  rhs_rows <- list()
  mcmc_ref_rows <- list()
  mcmc_draw_rows <- list()
  distance_rows <- list()
  chain_rows <- list()
  runtime_rows <- list()
  run_rows <- list()

  control_grid <- paste(app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid), collapse = ",")

  for (fixture in fixtures) {
    scenario_id <- fixture$scenario_id
    p <- ncol(fixture$Z)
    K <- length(fixture$tau)
    n_train <- length(fixture$y)
    reference_requested <- scenario_id %in% mcmc_reference_scenarios
    run_rows[[length(run_rows) + 1L]] <- data.frame(
      scenario_id = scenario_id,
      scenario_class = fixture$scenario_class,
      distribution_family = fixture$distribution_family,
      dynamics_class = fixture$dynamics_class,
      truth_quantile_method = fixture$truth_quantile_method,
      seed = fixture$seed,
      simulated_length = fixture$simulated_length,
      washout_length = fixture$washout_length,
      train_length = fixture$train_length,
      test_length = fixture$test_length,
      n_train = n_train,
      p = p,
      K = K,
      tau_grid = paste(fixture$tau, collapse = ","),
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = if (is.null(alpha_prior_mean)) "none" else paste(as.character(alpha_prior_mean), collapse = ","),
      alpha_prior_sd = alpha_prior_sd,
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = control_grid,
      rhs_vb_inner = rhs_vb_inner,
      mcmc_reference = reference_requested,
      n_chains = if (reference_requested) n_chains else 0L,
      mcmc_n_iter = if (reference_requested) mcmc_n_iter else 0L,
      mcmc_burn = if (reference_requested) mcmc_burn else 0L,
      mcmc_thin = if (reference_requested) mcmc_thin else 0L,
      no_test_leakage = all(fixture$split == "train") &&
        min(fixture$time_index) >= fixture$train_start &&
        max(fixture$time_index) <= fixture$train_end,
      notes = fixture$notes,
      stringsAsFactors = FALSE
    )

    t0 <- proc.time()[["elapsed"]]
    vb_adaptive <- app_joint_qvp_fit_al_vb_adaptive(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      tol = 1.0e-4,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      rhs_vb_inner = rhs_vb_inner
    )
    vb_elapsed <- proc.time()[["elapsed"]] - t0
    vb_fit <- vb_adaptive$fit
    vb_truth <- app_joint_qvp_qhat_truth_summary(fixture, vb_fit$qhat_mean, "vb", scenario_id)
    truth_truth <- app_joint_qvp_qhat_truth_summary(fixture, fixture$true_q, "truth", scenario_id)
    vb_pinball <- app_joint_qvp_phase2_pinball_rows(fixture, vb_fit$qhat_mean, "vb")
    truth_pinball <- app_joint_qvp_phase2_pinball_rows(fixture, fixture$true_q, "truth")

    fit_rows[[length(fit_rows) + 1L]] <- data.frame(
      scenario_id = scenario_id,
      fit = "vb",
      inference = "VB--LD",
      status = vb_fit$manifest$status[[1L]],
      converged = isTRUE(vb_fit$converged),
      n_iter = nrow(vb_fit$trace),
      n_train = n_train,
      p = p,
      K = K,
      tau_grid = paste(fixture$tau, collapse = ","),
      truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, vb_fit$qhat_mean),
      max_abs_hit_rate_error = max(abs(vb_truth$hit_rate_minus_tau)),
      pinball_mean_mean = mean(vb_pinball$pinball_mean),
      total_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
      objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
      elapsed_sec = vb_elapsed,
      init_source = NA_character_,
      no_test_leakage = run_rows[[length(run_rows)]]$no_test_leakage,
      stringsAsFactors = FALSE
    )
    truth_rows[[length(truth_rows) + 1L]] <- truth_truth
    truth_rows[[length(truth_rows) + 1L]] <- vb_truth
    pinball_rows[[length(pinball_rows) + 1L]] <- truth_pinball
    pinball_rows[[length(pinball_rows) + 1L]] <- vb_pinball
    hit_rows[[length(hit_rows) + 1L]] <- vb_truth[, c("case_id", "fit", "quantile_index", "tau", "empirical_hit_rate", "hit_rate_minus_tau"), drop = FALSE]
    crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
      data.frame(scenario_id = scenario_id, fit = "truth", chain_id = NA_integer_, stringsAsFactors = FALSE),
      fixture$crossing_diagnostics
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
      data.frame(scenario_id = scenario_id, fit = "vb", chain_id = NA_integer_, stringsAsFactors = FALSE),
      vb_fit$crossing_diagnostics
    )
    vb_audit_rows[[length(vb_audit_rows) + 1L]] <- cbind(
      data.frame(scenario_id = scenario_id, stringsAsFactors = FALSE),
      vb_adaptive$audit
    )
    objective_rows[[length(objective_rows) + 1L]] <- cbind(
      data.frame(scenario_id = scenario_id, fit = "vb", stringsAsFactors = FALSE),
      vb_fit$objective_diagnostics
    )
    final_elbo <- vb_fit$elbo_terms[vb_fit$elbo_terms$iter == max(vb_fit$elbo_terms$iter), , drop = FALSE]
    elbo_rows[[length(elbo_rows) + 1L]] <- cbind(
      data.frame(scenario_id = scenario_id, fit = "vb", stringsAsFactors = FALSE),
      final_elbo
    )
    rhs_rows[[length(rhs_rows) + 1L]] <- cbind(
      data.frame(scenario_id = scenario_id, fit = "vb", stringsAsFactors = FALSE),
      vb_fit$rhs_prior_summary
    )
    runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
      scenario_id = scenario_id,
      component = "VB adaptive",
      elapsed_sec = vb_elapsed,
      n_iter = nrow(vb_fit$trace),
      sec_per_iter = vb_elapsed / max(1L, nrow(vb_fit$trace)),
      stringsAsFactors = FALSE
    )

    if (reference_requested) {
      sigma_upper_bound <- max(1, sigma_upper_multiplier * max(vb_fit$sigma_mean))
      fits <- vector("list", n_chains)
      chain_seeds <- integer(n_chains)
      chain_draw_rows <- list()
      chain_crossing_rows <- list()
      mcmc_t0 <- proc.time()[["elapsed"]]
      for (chain_id in seq_len(n_chains)) {
        chain_seed <- fixture$seed + mcmc_seed_offset + (chain_id - 1L) * chain_seed_stride
        chain_seeds[[chain_id]] <- chain_seed
        chain_t0 <- proc.time()[["elapsed"]]
        fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
          y = fixture$y,
          Z = fixture$Z,
          tau = fixture$tau,
          n_iter = mcmc_n_iter,
          burn = mcmc_burn,
          thin = mcmc_thin,
          seed = chain_seed,
          kappa = kappa,
          tau0 = tau0,
          a_sigma = a_sigma,
          b_sigma = b_sigma,
          alpha_prior_mean = alpha_prior_mean,
          alpha_prior_sd = alpha_prior_sd,
          init = vb_fit,
          max_dense_dim = 100L,
          sigma_bounds = c(1.0e-8, sigma_upper_bound)
        )
        chain_elapsed <- proc.time()[["elapsed"]] - chain_t0
        chain_draw_rows[[length(chain_draw_rows) + 1L]] <- cbind(
          data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
          app_joint_qvp_mcmc_draw_summary(
            fits[[chain_id]],
            scenario_id,
            "synthetic_dgp_phase2",
            fixture$dynamics_class,
            sigma_bounds = c(1.0e-8, sigma_upper_bound)
          )
        )
        chain_crossing_rows[[length(chain_crossing_rows) + 1L]] <- cbind(
          data.frame(scenario_id = scenario_id, fit = sprintf("chain_%s", chain_id), chain_id = chain_id, stringsAsFactors = FALSE),
          fits[[chain_id]]$crossing_diagnostics
        )
        runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
          scenario_id = scenario_id,
          component = sprintf("MCMC chain %s", chain_id),
          elapsed_sec = chain_elapsed,
          n_iter = mcmc_n_iter,
          sec_per_iter = chain_elapsed / max(1L, mcmc_n_iter),
          stringsAsFactors = FALSE
        )
      }
      pooled <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, K, p, fixture$tau)
      mcmc_elapsed <- proc.time()[["elapsed"]] - mcmc_t0
      mcmc_truth <- app_joint_qvp_qhat_truth_summary(fixture, pooled$qhat_mean, "pooled_mcmc", scenario_id)
      mcmc_pinball <- app_joint_qvp_phase2_pinball_rows(fixture, pooled$qhat_mean, "pooled_mcmc")
      distance <- app_joint_qvp_vb_mcmc_distance_summary(
        vb_fit = vb_fit,
        mcmc_fit = pooled,
        case_id = scenario_id,
        stress_case = "synthetic_dgp_phase2",
        scenario = fixture$dynamics_class,
        Tn = n_train,
        p = p,
        K = K
      )
      chains <- app_joint_qvp_chain_to_pooled_summary(
        fits = fits,
        pooled_fit = pooled,
        Z = fixture$Z,
        case_id = scenario_id,
        stress_case = "synthetic_dgp_phase2",
        scenario = fixture$dynamics_class,
        Tn = n_train,
        p = p,
        K = K
      )
      chains$chain_seed <- chain_seeds[chains$chain_id]
      draw_summary <- do.call(rbind, chain_draw_rows)
      sigma_draws <- draw_summary[draw_summary$block == "sigma", , drop = FALSE]
      max_sigma_hit <- if (nrow(sigma_draws)) max(sigma_draws$upper_bound_hit_fraction, na.rm = TRUE) else NA_real_
      all_draws_finite <- all(draw_summary$all_finite)

      fit_rows[[length(fit_rows) + 1L]] <- data.frame(
        scenario_id = scenario_id,
        fit = "pooled_mcmc",
        inference = "MCMC reference",
        status = "reference_success",
        converged = NA,
        n_iter = mcmc_n_iter * n_chains,
        n_train = n_train,
        p = p,
        K = K,
        tau_grid = paste(fixture$tau, collapse = ","),
        truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, pooled$qhat_mean),
        max_abs_hit_rate_error = max(abs(mcmc_truth$hit_rate_minus_tau)),
        pinball_mean_mean = mean(mcmc_pinball$pinball_mean),
        total_crossing_pairs = sum(pooled$crossing_diagnostics$n_crossing_pairs),
        objective_status = NA_character_,
        elapsed_sec = mcmc_elapsed,
        init_source = pooled$init_source,
        no_test_leakage = run_rows[[length(run_rows)]]$no_test_leakage,
        stringsAsFactors = FALSE
      )
      truth_rows[[length(truth_rows) + 1L]] <- mcmc_truth
      pinball_rows[[length(pinball_rows) + 1L]] <- mcmc_pinball
      hit_rows[[length(hit_rows) + 1L]] <- mcmc_truth[, c("case_id", "fit", "quantile_index", "tau", "empirical_hit_rate", "hit_rate_minus_tau"), drop = FALSE]
      crossing_rows <- c(crossing_rows, chain_crossing_rows)
      crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
        data.frame(scenario_id = scenario_id, fit = "pooled_mcmc", chain_id = NA_integer_, stringsAsFactors = FALSE),
        pooled$crossing_diagnostics
      )
      mcmc_draw_rows[[length(mcmc_draw_rows) + 1L]] <- draw_summary
      distance_rows[[length(distance_rows) + 1L]] <- distance
      chain_rows[[length(chain_rows) + 1L]] <- chains
      mcmc_status <- if (!all_draws_finite || !identical(pooled$init_source, "provided") || sum(pooled$crossing_diagnostics$n_crossing_pairs) > 0) {
        "fail"
      } else if (is.finite(distance$max_normalized_distance[[1L]]) && distance$max_normalized_distance[[1L]] <= 5 && is.finite(max_sigma_hit) && max_sigma_hit <= 0) {
        "pass"
      } else {
        "review"
      }
      mcmc_ref_rows[[length(mcmc_ref_rows) + 1L]] <- data.frame(
        scenario_id = scenario_id,
        reference_requested = TRUE,
        reference_status = mcmc_status,
        init_source = pooled$init_source,
        n_chains = n_chains,
        n_keep_total = nrow(pooled$beta_draws),
        max_normalized_distance = distance$max_normalized_distance[[1L]],
        max_chain_to_pooled_normalized_distance = max(chains$max_normalized_to_pooled, na.rm = TRUE),
        all_draws_finite = all_draws_finite,
        note = "short VB-initialized MCMC implementation reference; not final posterior promotion evidence",
        stringsAsFactors = FALSE
      )
      runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
        scenario_id = scenario_id,
        component = "MCMC pooled total",
        elapsed_sec = mcmc_elapsed,
        n_iter = mcmc_n_iter * n_chains,
        sec_per_iter = mcmc_elapsed / max(1L, mcmc_n_iter * n_chains),
        stringsAsFactors = FALSE
      )
    } else {
      mcmc_ref_rows[[length(mcmc_ref_rows) + 1L]] <- data.frame(
        scenario_id = scenario_id,
        reference_requested = FALSE,
        reference_status = "skipped",
        init_source = NA_character_,
        n_chains = 0L,
        n_keep_total = 0L,
        max_normalized_distance = NA_real_,
        max_chain_to_pooled_normalized_distance = NA_real_,
        all_draws_finite = NA,
        note = "MCMC reference not requested for this Phase 2 scenario",
        stringsAsFactors = FALSE
      )
    }
  }

  run_config <- do.call(rbind, run_rows)
  fit_summary <- do.call(rbind, fit_rows)
  truth_fit_summary <- do.call(rbind, truth_rows)
  names(truth_fit_summary)[names(truth_fit_summary) == "case_id"] <- "scenario_id"
  pinball_summary <- do.call(rbind, pinball_rows)
  hit_rate_summary <- do.call(rbind, hit_rows)
  names(hit_rate_summary)[names(hit_rate_summary) == "case_id"] <- "scenario_id"
  crossing_summary <- do.call(rbind, crossing_rows)
  vb_convergence_audit <- do.call(rbind, vb_audit_rows)
  objective_diagnostics <- do.call(rbind, objective_rows)
  elbo_terms <- do.call(rbind, elbo_rows)
  rhs_prior_summary <- do.call(rbind, rhs_rows)
  mcmc_reference_summary <- do.call(rbind, mcmc_ref_rows)
  mcmc_draw_summary <- if (length(mcmc_draw_rows)) do.call(rbind, mcmc_draw_rows) else app_joint_qvp_phase2_empty_mcmc_draw_summary()
  vb_mcmc_distance_summary <- if (length(distance_rows)) do.call(rbind, distance_rows) else app_joint_qvp_phase2_empty_vb_mcmc_distance_summary()
  chain_summary <- if (length(chain_rows)) do.call(rbind, chain_rows) else app_joint_qvp_phase2_empty_chain_summary()
  runtime_summary <- do.call(rbind, runtime_rows)

  fit_validation_assessment <- app_joint_qvp_phase2_assessment_rows(
    fit_summary = fit_summary,
    truth_fit_summary = truth_fit_summary,
    mcmc_reference_summary = mcmc_reference_summary,
    source_hashes_verified = source_hashes_verified
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase2_readme_lines(run_config, fit_validation_assessment), readme_path, useBytes = TRUE)

  fixture_source_manifest <- tables$fixture_source_manifest
  fixture_source_manifest$fixture_dir <- vapply(fixture_source_manifest$fixture_dir, app_prefer_repo_relative_path, character(1L))
  fixture_source_manifest$absolute_path <- vapply(fixture_source_manifest$absolute_path, app_prefer_repo_relative_path, character(1L))

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(fixture_source_manifest, file.path(out_dir, "fixture_source_manifest.csv")),
    fit_validation_assessment = app_joint_qvp_write_csv(fit_validation_assessment, file.path(out_dir, "fit_validation_assessment.csv")),
    fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
    truth_fit_summary = app_joint_qvp_write_csv(truth_fit_summary, file.path(out_dir, "truth_fit_summary.csv")),
    pinball_summary = app_joint_qvp_write_csv(pinball_summary, file.path(out_dir, "pinball_summary.csv")),
    hit_rate_summary = app_joint_qvp_write_csv(hit_rate_summary, file.path(out_dir, "hit_rate_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence_audit, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective_diagnostics, file.path(out_dir, "objective_diagnostics.csv")),
    elbo_terms = app_joint_qvp_write_csv(elbo_terms, file.path(out_dir, "elbo_terms.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(rhs_prior_summary, file.path(out_dir, "rhs_prior_summary.csv")),
    mcmc_reference_summary = app_joint_qvp_write_csv(mcmc_reference_summary, file.path(out_dir, "mcmc_reference_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(mcmc_draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    chain_summary = app_joint_qvp_write_csv(chain_summary, file.path(out_dir, "chain_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance_summary, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime_summary, file.path(out_dir, "runtime_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    fixture_dir = normalizePath(fixture_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    run_config = run_config,
    fit_validation_assessment = fit_validation_assessment,
    fit_summary = fit_summary,
    truth_fit_summary = truth_fit_summary,
    mcmc_reference_summary = mcmc_reference_summary
  )
}

app_joint_qvp_default_synthetic_dgp_forecast_validation_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_validation_phase3_20260702")
}

app_joint_qvp_phase3_feature_columns <- function(design_block) {
  app_joint_qvp_phase2_feature_columns(design_block)
}

app_joint_qvp_phase3_forecast_fixture_from_tables <- function(tables, scenario_id) {
  scenario_id <- as.character(scenario_id)
  observed <- tables$observed_series[tables$observed_series$scenario_id == scenario_id, , drop = FALSE]
  design <- tables$design_matrix[tables$design_matrix$scenario_id == scenario_id, , drop = FALSE]
  truth <- tables$true_quantile_wide[tables$true_quantile_wide$scenario_id == scenario_id, , drop = FALSE]
  truth_long <- tables$true_quantile_long[tables$true_quantile_long$scenario_id == scenario_id, , drop = FALSE]
  split_meta <- tables$split_metadata[tables$split_metadata$scenario_id == scenario_id, , drop = FALSE]
  summary <- tables$scenario_summary[tables$scenario_summary$scenario_id == scenario_id, , drop = FALSE]
  registry <- tables$frozen_registry[tables$frozen_registry$scenario_id == scenario_id, , drop = FALSE]
  if (!nrow(observed) || !nrow(design) || !nrow(truth) || !nrow(truth_long) || nrow(split_meta) != 1L || nrow(summary) != 1L) {
    stop(sprintf("Phase 1 forecast fixture tables are incomplete for scenario '%s'.", scenario_id), call. = FALSE)
  }
  observed <- observed[order(observed$time_index), , drop = FALSE]
  design <- design[order(design$time_index), , drop = FALSE]
  truth <- truth[order(truth$time_index), , drop = FALSE]
  if (!identical(observed$time_index, design$time_index) || !identical(observed$time_index, truth$time_index)) {
    stop(sprintf("Observed, design, and truth time indices are misaligned for scenario '%s'.", scenario_id), call. = FALSE)
  }
  retained <- observed$split != "washout"
  if (!any(retained) || !any(observed$split == "test")) {
    stop(sprintf("Forecast validation requires retained and test rows for scenario '%s'.", scenario_id), call. = FALSE)
  }
  retained_observed <- observed[retained, , drop = FALSE]
  retained_design <- design[retained, , drop = FALSE]
  retained_truth <- truth[retained, , drop = FALSE]
  feature_cols <- app_joint_qvp_phase3_feature_columns(retained_design)
  if (!length(feature_cols)) stop(sprintf("No finite forecast feature columns found for scenario '%s'.", scenario_id), call. = FALSE)
  Z <- as.matrix(retained_design[, feature_cols, drop = FALSE])
  storage.mode(Z) <- "double"
  q_cols <- grep("^q_tau_", names(retained_truth), value = TRUE)
  tau <- app_joint_qvp_parse_tau_spec(summary$tau_grid[[1L]])
  if (length(q_cols) != length(tau)) {
    stop(sprintf("Tau grid and forecast truth columns do not match for scenario '%s'.", scenario_id), call. = FALSE)
  }
  long_tau <- sort(unique(as.numeric(truth_long$tau)))
  if (!identical(round(long_tau, 12), round(tau, 12)) ||
      nrow(truth_long[truth_long$split != "washout", , drop = FALSE]) != sum(retained) * length(tau) ||
      any(!is.finite(truth_long$true_quantile))) {
    stop(sprintf("Long-format forecast truth table is malformed for scenario '%s'.", scenario_id), call. = FALSE)
  }
  true_q <- as.matrix(retained_truth[, q_cols, drop = FALSE])
  storage.mode(true_q) <- "double"
  colnames(true_q) <- q_cols
  y <- as.numeric(retained_observed$y)
  sigma <- as.numeric(retained_observed$sigma)
  if (any(!is.finite(y)) || any(!is.finite(Z)) || any(!is.finite(true_q)) || any(!is.finite(sigma)) || any(sigma <= 0)) {
    stop(sprintf("Non-finite retained forecast fixture values found for scenario '%s'.", scenario_id), call. = FALSE)
  }
  test_pos <- which(retained_observed$split == "test")
  if (length(test_pos) != split_meta$test_length[[1L]]) {
    stop(sprintf("Test split length is malformed for scenario '%s'.", scenario_id), call. = FALSE)
  }
  if (any(retained_observed$time_index[test_pos] < split_meta$test_start[[1L]] |
      retained_observed$time_index[test_pos] > split_meta$test_end[[1L]])) {
    stop(sprintf("Test split time window is malformed for scenario '%s'.", scenario_id), call. = FALSE)
  }
  crossing <- app_joint_qvp_crossing_diagnostics(true_q, tau)
  list(
    scenario_id = scenario_id,
    case_id = scenario_id,
    scenario_class = summary$scenario_class[[1L]],
    distribution_family = summary$distribution_family[[1L]],
    dynamics_class = summary$dynamics_class[[1L]],
    truth_quantile_method = summary$truth_quantile_method[[1L]],
    y = y,
    Z = Z,
    tau = tau,
    true_q = true_q,
    sigma = sigma,
    time_index = retained_observed$time_index,
    split = retained_observed$split,
    split_index = retained_observed$split_index,
    retained_time_index = retained_observed$retained_time_index,
    test_pos = test_pos,
    feature_cols = feature_cols,
    simulated_length = split_meta$simulated_length[[1L]],
    washout_length = split_meta$washout_length[[1L]],
    train_length = split_meta$train_length[[1L]],
    test_length = split_meta$test_length[[1L]],
    train_start = split_meta$train_start[[1L]],
    train_end = split_meta$train_end[[1L]],
    test_start = split_meta$test_start[[1L]],
    test_end = split_meta$test_end[[1L]],
    seed = if (nrow(registry)) as.integer(registry$seed[[1L]]) else as.integer(summary$seed[[1L]]),
    dynamic = summary$dynamics_class[[1L]],
    likelihood = paste0("standardized_", summary$distribution_family[[1L]]),
    notes = summary$notes[[1L]],
    crossing_diagnostics = crossing
  )
}

app_joint_qvp_phase3_select_origin_positions <- function(
  fixture,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = Inf
) {
  forecast_origin_stride <- as.integer(forecast_origin_stride)[[1L]]
  if (!is.finite(forecast_origin_stride) || forecast_origin_stride <= 0L) {
    stop("forecast_origin_stride must be a positive integer.", call. = FALSE)
  }
  selected <- fixture$test_pos[seq.int(1L, length(fixture$test_pos), by = forecast_origin_stride)]
  max_origins <- suppressWarnings(as.numeric(max_origins_per_scenario)[[1L]])
  if (is.finite(max_origins)) selected <- head(selected, as.integer(max_origins))
  if (!length(selected)) stop(sprintf("No forecast origins selected for scenario '%s'.", fixture$scenario_id), call. = FALSE)
  selected
}

app_joint_qvp_phase3_origin_rows <- function(
  fixture,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = Inf
) {
  selected <- app_joint_qvp_phase3_select_origin_positions(
    fixture,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = max_origins_per_scenario
  )
  rows <- lapply(seq_along(selected), function(ii) {
    pos <- selected[[ii]]
    forecast_time <- fixture$time_index[[pos]]
    available_pos <- which(fixture$time_index < forecast_time)
    if (!length(available_pos)) {
      stop(sprintf("No available fit rows before forecast origin %s for scenario '%s'.", ii, fixture$scenario_id), call. = FALSE)
    }
    future_leak <- any(fixture$time_index[available_pos] >= forecast_time) ||
      any(fixture$split[available_pos] == "test" & fixture$time_index[available_pos] >= forecast_time)
    data.frame(
      scenario_id = fixture$scenario_id,
      origin_index = ii,
      forecast_time_index = forecast_time,
      forecast_retained_index = fixture$retained_time_index[[pos]],
      forecast_split_index = fixture$split_index[[pos]],
      forecast_horizon = 1L,
      forecast_role = fixture$split[[pos]],
      target_y = fixture$y[[pos]],
      available_fit_window_start = min(fixture$time_index[available_pos]),
      available_fit_window_end = max(fixture$time_index[available_pos]),
      available_fit_n = length(available_pos),
      available_train_n = sum(fixture$split[available_pos] == "train"),
      available_previous_test_n = sum(fixture$split[available_pos] == "test"),
      no_future_test_leakage = !future_leak,
      forecast_retained_pos = pos,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_phase3_fit_window <- function(fixture, forecast_time_index) {
  fit_pos <- which(fixture$time_index < forecast_time_index)
  if (!length(fit_pos)) stop("No fit rows are available before the requested forecast time.", call. = FALSE)
  if (any(fixture$time_index[fit_pos] >= forecast_time_index)) {
    stop("Forecast fit window includes current or future observations.", call. = FALSE)
  }
  list(
    pos = fit_pos,
    y = fixture$y[fit_pos],
    Z = fixture$Z[fit_pos, , drop = FALSE],
    true_q = fixture$true_q[fit_pos, , drop = FALSE],
    time_index = fixture$time_index[fit_pos],
    split = fixture$split[fit_pos]
  )
}

app_joint_qvp_phase3_predict_row <- function(fit, z_row, tau) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  z_row <- matrix(as.numeric(z_row), nrow = 1L)
  p <- ncol(z_row)
  beta <- app_joint_qvp_beta_matrix(fit$beta_mean, K, p)
  qhat <- as.numeric(z_row %*% beta + fit$alpha_mean)
  names(qhat) <- paste0("tau_", tau)
  qhat
}

app_joint_qvp_phase3_pinball_loss <- function(y, q, tau) {
  e <- as.numeric(y) - as.numeric(q)
  ifelse(e >= 0, tau * e, (tau - 1) * e)
}

app_joint_qvp_phase3_interval_score <- function(y, lower, upper, alpha) {
  width <- upper - lower
  width + (2 / alpha) * (lower - y) * (y < lower) + (2 / alpha) * (y - upper) * (y > upper)
}

app_joint_qvp_phase3_forecast_rows <- function(fixture, origin, qhat, method = "vb") {
  pos <- origin$forecast_retained_pos[[1L]]
  rows <- lapply(seq_along(fixture$tau), function(k) {
    tau <- fixture$tau[[k]]
    y <- fixture$y[[pos]]
    truth <- fixture$true_q[pos, k]
    data.frame(
      scenario_id = fixture$scenario_id,
      method = method,
      origin_index = origin$origin_index[[1L]],
      forecast_time_index = origin$forecast_time_index[[1L]],
      forecast_retained_index = origin$forecast_retained_index[[1L]],
      forecast_split_index = origin$forecast_split_index[[1L]],
      forecast_horizon = origin$forecast_horizon[[1L]],
      quantile_index = k,
      tau = tau,
      qhat = qhat[[k]],
      true_quantile = truth,
      truth_error = qhat[[k]] - truth,
      abs_truth_error = abs(qhat[[k]] - truth),
      squared_truth_error = (qhat[[k]] - truth)^2,
      y = y,
      hit = y <= qhat[[k]],
      truth_hit = y <= truth,
      pinball_loss = app_joint_qvp_phase3_pinball_loss(y, qhat[[k]], tau),
      truth_pinball_loss = app_joint_qvp_phase3_pinball_loss(y, truth, tau),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_phase3_contract_forecast <- function(qhat_raw, tau, crossing_tolerance = 1.0e-10) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  qhat_raw <- as.numeric(qhat_raw)
  if (length(qhat_raw) != length(tau)) stop("qhat_raw and tau must have the same length.", call. = FALSE)
  qhat_contract <- app_isotonic_quantiles(tau, qhat_raw)
  qhat_contract <- as.numeric(qhat_contract)
  names(qhat_contract) <- names(qhat_raw) %||% paste0("tau_", tau)
  names(qhat_raw) <- names(qhat_contract)
  raw_diff <- diff(qhat_raw)
  contract_diff <- diff(qhat_contract)
  raw_cross <- raw_diff < -crossing_tolerance
  contract_cross <- contract_diff < -crossing_tolerance
  adjustment <- qhat_contract - qhat_raw
  list(
    qhat_raw = qhat_raw,
    qhat_contract = qhat_contract,
    raw_cross = raw_cross,
    contract_cross = contract_cross,
    adjustment = adjustment,
    max_abs_adjustment = if (length(adjustment)) max(abs(adjustment)) else 0,
    sum_abs_adjustment = if (length(adjustment)) sum(abs(adjustment)) else 0,
    n_adjusted_quantiles = sum(abs(adjustment) > crossing_tolerance),
    n_raw_crossing_pairs = sum(raw_cross, na.rm = TRUE),
    n_contract_crossing_pairs = sum(contract_cross, na.rm = TRUE),
    raw_max_crossing_magnitude = if (any(raw_cross, na.rm = TRUE)) max(-raw_diff[raw_cross], na.rm = TRUE) else 0,
    contract_max_crossing_magnitude = if (any(contract_cross, na.rm = TRUE)) max(-contract_diff[contract_cross], na.rm = TRUE) else 0,
    affected_tau_pairs = if (any(raw_cross, na.rm = TRUE)) {
      paste(sprintf("%s-%s", tau[which(raw_cross)], tau[which(raw_cross) + 1L]), collapse = ";")
    } else {
      ""
    }
  )
}

app_joint_qvp_phase3_monotone_adjustment_row <- function(fixture, origin, contract, method = "vb") {
  data.frame(
    scenario_id = fixture$scenario_id,
    method = method,
    origin_index = origin$origin_index[[1L]],
    forecast_time_index = origin$forecast_time_index[[1L]],
    forecast_retained_index = origin$forecast_retained_index[[1L]],
    n_quantiles = length(fixture$tau),
    n_adjusted_quantiles = contract$n_adjusted_quantiles,
    max_abs_adjustment = contract$max_abs_adjustment,
    sum_abs_adjustment = contract$sum_abs_adjustment,
    n_raw_crossing_pairs = contract$n_raw_crossing_pairs,
    raw_max_crossing_magnitude = contract$raw_max_crossing_magnitude,
    n_contract_crossing_pairs = contract$n_contract_crossing_pairs,
    contract_max_crossing_magnitude = contract$contract_max_crossing_magnitude,
    affected_tau_pairs = contract$affected_tau_pairs,
    adjustment_status = if (contract$n_contract_crossing_pairs > 0L) {
      "fail"
    } else if (contract$n_adjusted_quantiles > 0L) {
      "review"
    } else {
      "pass"
    },
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase3_truth_comparison_summary <- function(forecast_quantiles) {
  keys <- unique(forecast_quantiles[, c("scenario_id", "method", "quantile_index", "tau"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- forecast_quantiles$scenario_id == keys$scenario_id[[ii]] &
      forecast_quantiles$method == keys$method[[ii]] &
      forecast_quantiles$quantile_index == keys$quantile_index[[ii]]
    block <- forecast_quantiles[idx, , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_forecasts = nrow(block),
      rmse_to_truth = sqrt(mean(block$truth_error^2)),
      mae_to_truth = mean(abs(block$truth_error)),
      bias_to_truth = mean(block$truth_error),
      max_abs_error_to_truth = max(abs(block$truth_error)),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_pinball_summary <- function(forecast_quantiles) {
  keys <- unique(forecast_quantiles[, c("scenario_id", "method", "quantile_index", "tau"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- forecast_quantiles$scenario_id == keys$scenario_id[[ii]] &
      forecast_quantiles$method == keys$method[[ii]] &
      forecast_quantiles$quantile_index == keys$quantile_index[[ii]]
    block <- forecast_quantiles[idx, , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_forecasts = nrow(block),
      pinball_mean = mean(block$pinball_loss),
      pinball_sum = sum(block$pinball_loss),
      truth_pinball_mean = mean(block$truth_pinball_loss),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_hit_rate_summary <- function(forecast_quantiles) {
  keys <- unique(forecast_quantiles[, c("scenario_id", "method", "quantile_index", "tau"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- forecast_quantiles$scenario_id == keys$scenario_id[[ii]] &
      forecast_quantiles$method == keys$method[[ii]] &
      forecast_quantiles$quantile_index == keys$quantile_index[[ii]]
    block <- forecast_quantiles[idx, , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_forecasts = nrow(block),
      empirical_hit_rate = mean(block$hit),
      hit_rate_minus_tau = mean(block$hit) - keys$tau[[ii]],
      oracle_truth_hit_rate = mean(block$truth_hit),
      oracle_truth_hit_minus_tau = mean(block$truth_hit) - keys$tau[[ii]],
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_interval_pairs <- function(tau, tolerance = 1.0e-10) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  lowers <- tau[tau < 0.5]
  rows <- list()
  for (lo in lowers) {
    hi <- 1 - lo
    match_idx <- which(abs(tau - hi) <= tolerance)
    if (length(match_idx)) {
      rows[[length(rows) + 1L]] <- data.frame(
        lower_tau = lo,
        upper_tau = tau[match_idx[[1L]]],
        nominal = tau[match_idx[[1L]]] - lo,
        alpha = 1 - (tau[match_idx[[1L]]] - lo),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) {
    return(data.frame(lower_tau = numeric(), upper_tau = numeric(), nominal = numeric(), alpha = numeric()))
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_interval_detail <- function(forecast_quantiles) {
  rows <- list()
  scenario_methods <- unique(forecast_quantiles[, c("scenario_id", "method"), drop = FALSE])
  for (ii in seq_len(nrow(scenario_methods))) {
    block <- forecast_quantiles[
      forecast_quantiles$scenario_id == scenario_methods$scenario_id[[ii]] &
        forecast_quantiles$method == scenario_methods$method[[ii]],
      ,
      drop = FALSE
    ]
    pairs <- app_joint_qvp_phase3_interval_pairs(sort(unique(block$tau)))
    if (!nrow(pairs)) next
    origins <- unique(block[, c("origin_index", "forecast_time_index", "forecast_horizon"), drop = FALSE])
    for (jj in seq_len(nrow(origins))) {
      oblock <- block[block$origin_index == origins$origin_index[[jj]], , drop = FALSE]
      y <- oblock$y[[1L]]
      for (kk in seq_len(nrow(pairs))) {
        lower <- oblock[abs(oblock$tau - pairs$lower_tau[[kk]]) <= 1.0e-10, , drop = FALSE]
        upper <- oblock[abs(oblock$tau - pairs$upper_tau[[kk]]) <= 1.0e-10, , drop = FALSE]
        if (nrow(lower) != 1L || nrow(upper) != 1L) next
        rows[[length(rows) + 1L]] <- data.frame(
          scenario_id = scenario_methods$scenario_id[[ii]],
          method = scenario_methods$method[[ii]],
          origin_index = origins$origin_index[[jj]],
          forecast_time_index = origins$forecast_time_index[[jj]],
          forecast_horizon = origins$forecast_horizon[[jj]],
          lower_tau = pairs$lower_tau[[kk]],
          upper_tau = pairs$upper_tau[[kk]],
          nominal = pairs$nominal[[kk]],
          alpha = pairs$alpha[[kk]],
          lower_qhat = lower$qhat[[1L]],
          upper_qhat = upper$qhat[[1L]],
          lower_true_quantile = lower$true_quantile[[1L]],
          upper_true_quantile = upper$true_quantile[[1L]],
          y = y,
          covered = y >= lower$qhat[[1L]] && y <= upper$qhat[[1L]],
          truth_covered = y >= lower$true_quantile[[1L]] && y <= upper$true_quantile[[1L]],
          interval_width = upper$qhat[[1L]] - lower$qhat[[1L]],
          truth_interval_width = upper$true_quantile[[1L]] - lower$true_quantile[[1L]],
          interval_score = app_joint_qvp_phase3_interval_score(
            y,
            lower$qhat[[1L]],
            upper$qhat[[1L]],
            pairs$alpha[[kk]]
          ),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(
      scenario_id = character(), method = character(), origin_index = integer(),
      forecast_time_index = integer(), forecast_horizon = integer(), lower_tau = numeric(),
      upper_tau = numeric(), nominal = numeric(), alpha = numeric(), lower_qhat = numeric(),
      upper_qhat = numeric(), lower_true_quantile = numeric(), upper_true_quantile = numeric(),
      y = numeric(), covered = logical(), truth_covered = logical(), interval_width = numeric(),
      truth_interval_width = numeric(), interval_score = numeric(), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_interval_coverage_summary <- function(interval_detail) {
  if (!nrow(interval_detail)) {
    return(data.frame(
      scenario_id = character(), method = character(), lower_tau = numeric(), upper_tau = numeric(),
      nominal = numeric(), n_forecasts = integer(), empirical_coverage = numeric(),
      coverage_minus_nominal = numeric(), oracle_truth_coverage = numeric(),
      oracle_truth_coverage_minus_nominal = numeric(), stringsAsFactors = FALSE
    ))
  }
  keys <- unique(interval_detail[, c("scenario_id", "method", "lower_tau", "upper_tau", "nominal"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- interval_detail$scenario_id == keys$scenario_id[[ii]] &
      interval_detail$method == keys$method[[ii]] &
      interval_detail$lower_tau == keys$lower_tau[[ii]] &
      interval_detail$upper_tau == keys$upper_tau[[ii]]
    block <- interval_detail[idx, , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_forecasts = nrow(block),
      empirical_coverage = mean(block$covered),
      coverage_minus_nominal = mean(block$covered) - keys$nominal[[ii]],
      oracle_truth_coverage = mean(block$truth_covered),
      oracle_truth_coverage_minus_nominal = mean(block$truth_covered) - keys$nominal[[ii]],
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_interval_score_summary <- function(interval_detail) {
  if (!nrow(interval_detail)) {
    return(data.frame(
      scenario_id = character(), method = character(), lower_tau = numeric(), upper_tau = numeric(),
      nominal = numeric(), alpha = numeric(), n_forecasts = integer(), interval_score_mean = numeric(),
      interval_score_sum = numeric(), interval_width_mean = numeric(), truth_interval_width_mean = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  keys <- unique(interval_detail[, c("scenario_id", "method", "lower_tau", "upper_tau", "nominal", "alpha"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- interval_detail$scenario_id == keys$scenario_id[[ii]] &
      interval_detail$method == keys$method[[ii]] &
      interval_detail$lower_tau == keys$lower_tau[[ii]] &
      interval_detail$upper_tau == keys$upper_tau[[ii]]
    block <- interval_detail[idx, , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_forecasts = nrow(block),
      interval_score_mean = mean(block$interval_score),
      interval_score_sum = sum(block$interval_score),
      interval_width_mean = mean(block$interval_width),
      truth_interval_width_mean = mean(block$truth_interval_width),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_wis_summary <- function(forecast_quantiles, interval_detail) {
  if (!nrow(interval_detail)) {
    return(data.frame(
      scenario_id = character(), method = character(), n_origins = integer(),
      wis_mean = numeric(), wis_sum = numeric(), median_abs_error_mean = numeric(),
      n_intervals = integer(), stringsAsFactors = FALSE
    ))
  }
  origin_keys <- unique(forecast_quantiles[, c("scenario_id", "method", "origin_index"), drop = FALSE])
  detail_rows <- list()
  for (ii in seq_len(nrow(origin_keys))) {
    qblock <- forecast_quantiles[
      forecast_quantiles$scenario_id == origin_keys$scenario_id[[ii]] &
        forecast_quantiles$method == origin_keys$method[[ii]] &
        forecast_quantiles$origin_index == origin_keys$origin_index[[ii]],
      ,
      drop = FALSE
    ]
    iblock <- interval_detail[
      interval_detail$scenario_id == origin_keys$scenario_id[[ii]] &
        interval_detail$method == origin_keys$method[[ii]] &
        interval_detail$origin_index == origin_keys$origin_index[[ii]],
      ,
      drop = FALSE
    ]
    median_row <- qblock[abs(qblock$tau - 0.5) <= 1.0e-10, , drop = FALSE]
    if (!nrow(median_row) || !nrow(iblock)) next
    median_abs <- abs(qblock$y[[1L]] - median_row$qhat[[1L]])
    weighted_intervals <- sum((iblock$alpha / 2) * iblock$interval_score)
    wis <- (0.5 * median_abs + weighted_intervals) / (0.5 + nrow(iblock))
    detail_rows[[length(detail_rows) + 1L]] <- data.frame(
      scenario_id = origin_keys$scenario_id[[ii]],
      method = origin_keys$method[[ii]],
      origin_index = origin_keys$origin_index[[ii]],
      wis = wis,
      median_abs_error = median_abs,
      n_intervals = nrow(iblock),
      stringsAsFactors = FALSE
    )
  }
  if (!length(detail_rows)) {
    return(data.frame(
      scenario_id = character(), method = character(), n_origins = integer(),
      wis_mean = numeric(), wis_sum = numeric(), median_abs_error_mean = numeric(),
      n_intervals = integer(), stringsAsFactors = FALSE
    ))
  }
  detail <- do.call(rbind, detail_rows)
  keys <- unique(detail[, c("scenario_id", "method"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    block <- detail[detail$scenario_id == keys$scenario_id[[ii]] & detail$method == keys$method[[ii]], , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_origins = nrow(block),
      wis_mean = mean(block$wis),
      wis_sum = sum(block$wis),
      median_abs_error_mean = mean(block$median_abs_error),
      n_intervals = max(block$n_intervals),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_crps_grid_summary <- function(forecast_quantiles) {
  origin_keys <- unique(forecast_quantiles[, c("scenario_id", "method", "origin_index"), drop = FALSE])
  detail_rows <- vector("list", nrow(origin_keys))
  for (ii in seq_len(nrow(origin_keys))) {
    block <- forecast_quantiles[
      forecast_quantiles$scenario_id == origin_keys$scenario_id[[ii]] &
        forecast_quantiles$method == origin_keys$method[[ii]] &
        forecast_quantiles$origin_index == origin_keys$origin_index[[ii]],
      ,
      drop = FALSE
    ]
    block <- block[order(block$tau), , drop = FALSE]
    loss <- app_joint_qvp_phase3_pinball_loss(block$y[[1L]], block$qhat, block$tau)
    crps <- if (nrow(block) >= 2L) 2 * sum(diff(block$tau) * (head(loss, -1L) + tail(loss, -1L)) / 2) else NA_real_
    detail_rows[[ii]] <- data.frame(
      origin_keys[ii, , drop = FALSE],
      crps_grid = crps,
      n_quantiles = nrow(block),
      stringsAsFactors = FALSE
    )
  }
  detail <- do.call(rbind, detail_rows)
  keys <- unique(detail[, c("scenario_id", "method"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    block <- detail[detail$scenario_id == keys$scenario_id[[ii]] & detail$method == keys$method[[ii]], , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_origins = nrow(block),
      crps_grid_mean = mean(block$crps_grid),
      crps_grid_sum = sum(block$crps_grid),
      n_quantiles = max(block$n_quantiles),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_overall_truth_distance <- function(block) {
  err <- block$qhat - block$true_quantile
  sqrt(sum(err^2)) / (sqrt(length(err)) * (1 + sqrt(mean(block$true_quantile^2))))
}

app_joint_qvp_phase3_assessment_rows <- function(
  run_config,
  forecast_quantiles,
  hit_rate_summary,
  crossing_summary,
  vb_convergence_audit,
  objective_diagnostics,
  raw_crossing_summary = NULL,
  forecast_monotone_adjustment = NULL,
  source_hashes_verified = TRUE,
  truth_distance_pass = 1.5,
  hit_rate_floor = 0.10,
  hit_rate_multiplier = 2.5
) {
  scenarios <- unique(run_config$scenario_id)
  rows <- vector("list", length(scenarios))
  for (ii in seq_along(scenarios)) {
    scenario_id <- scenarios[[ii]]
    cfg <- run_config[run_config$scenario_id == scenario_id, , drop = FALSE]
    qblock <- forecast_quantiles[forecast_quantiles$scenario_id == scenario_id, , drop = FALSE]
    hblock <- hit_rate_summary[hit_rate_summary$scenario_id == scenario_id, , drop = FALSE]
    cblock <- crossing_summary[crossing_summary$scenario_id == scenario_id, , drop = FALSE]
    rblock <- if (is.null(raw_crossing_summary)) data.frame() else raw_crossing_summary[raw_crossing_summary$scenario_id == scenario_id, , drop = FALSE]
    mblock <- if (is.null(forecast_monotone_adjustment)) data.frame() else forecast_monotone_adjustment[forecast_monotone_adjustment$scenario_id == scenario_id, , drop = FALSE]
    ablock <- vb_convergence_audit[vb_convergence_audit$scenario_id == scenario_id, , drop = FALSE]
    oblock <- objective_diagnostics[objective_diagnostics$scenario_id == scenario_id, , drop = FALSE]
    truth_distance <- if (nrow(qblock)) app_joint_qvp_phase3_overall_truth_distance(qblock) else NA_real_
    hit_allowed <- if (nrow(hblock)) {
      pmax(hit_rate_floor, hit_rate_multiplier * sqrt(hblock$tau * (1 - hblock$tau) / pmax(1L, hblock$n_forecasts)))
    } else {
      numeric()
    }
    hit_error <- if (nrow(hblock)) abs(hblock$hit_rate_minus_tau) else numeric()
    finite_required <- nrow(qblock) > 0L &&
      isTRUE(source_hashes_verified) &&
      all(is.finite(c(
        qblock$qhat,
        qblock$true_quantile,
        qblock$y,
        qblock$pinball_loss,
        qblock$truth_error,
        truth_distance
      ))) &&
      all(is.finite(hblock$empirical_hit_rate)) &&
      all(is.finite(cblock$n_crossing_pairs))
    total_crossing <- if (nrow(cblock)) sum(cblock$n_crossing_pairs) else NA_integer_
    raw_crossing <- if (nrow(rblock)) sum(rblock$n_crossing_pairs) else 0L
    adjusted_origins <- if (nrow(mblock)) sum(mblock$n_adjusted_quantiles > 0L) else 0L
    max_monotone_adjustment <- if (nrow(mblock)) max(mblock$max_abs_adjustment, na.rm = TRUE) else 0
    monotone_adjustment_review <- adjusted_origins > 0L
    leakage_fail <- !all(cfg$no_future_test_leakage)
    implementation_fail <- !finite_required || leakage_fail || !is.finite(total_crossing) || total_crossing > 0L
    refit_audit <- ablock[ablock$refit, , drop = FALSE]
    vb_review <- nrow(refit_audit) &&
      any(!app_as_bool_vec(refit_audit$converged) | as.character(refit_audit$status) != "prototype_success")
    objective_review <- nrow(oblock) && any(as.character(oblock$objective_status) != "pass")
    implementation_status <- if (implementation_fail) {
      "fail"
    } else if (vb_review || monotone_adjustment_review) {
      "review"
    } else {
      "pass"
    }
    truth_distance_status <- if (is.finite(truth_distance) && truth_distance <= truth_distance_pass) "pass" else "review"
    hit_rate_status <- if (length(hit_error) && all(hit_error <= hit_allowed, na.rm = FALSE)) "pass" else "review"
    objective_status <- if (objective_review) "review" else "pass"
    gate_status <- if (implementation_status == "fail") {
      "fail"
    } else if (any(c(implementation_status, truth_distance_status, hit_rate_status, objective_status) == "review")) {
      "review"
    } else {
      "pass"
    }
    reasons <- c(
      if (!isTRUE(source_hashes_verified)) "fixture source hash failure",
      if (!finite_required) "non-finite forecast values or scores",
      if (leakage_fail) "train/test leakage",
      if (is.finite(total_crossing) && total_crossing > 0L) "forecast quantile crossings",
      if (raw_crossing > 0L) "raw forecast quantile crossings adjusted by monotone contract",
      if (monotone_adjustment_review) "monotone forecast adjustment review",
      if (vb_review) "VB convergence review",
      if (!identical(truth_distance_status, "pass")) "truth-distance review",
      if (!identical(hit_rate_status, "pass")) "hit-rate review",
      if (!identical(objective_status, "pass")) "objective review"
    )
    rows[[ii]] <- data.frame(
      scenario_id = scenario_id,
      implementation_status = implementation_status,
      truth_distance_status = truth_distance_status,
      hit_rate_status = hit_rate_status,
      objective_status = objective_status,
      gate_status = gate_status,
      n_forecast_origins = length(unique(qblock$origin_index)),
      n_quantile_forecasts = nrow(qblock),
      total_crossing_pairs = total_crossing,
      raw_crossing_pairs = raw_crossing,
      monotone_adjusted_origins = adjusted_origins,
      max_monotone_adjustment = max_monotone_adjustment,
      truth_normalized_qhat_distance = truth_distance,
      truth_distance_pass_threshold = truth_distance_pass,
      max_abs_hit_rate_error = if (length(hit_error)) max(hit_error) else NA_real_,
      max_hit_rate_allowed = if (length(hit_allowed)) max(hit_allowed) else NA_real_,
      note = app_joint_qvp_ts_assessment_note(reasons),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase3_readme_lines <- function(run_config, assessment) {
  status_counts <- table(assessment$gate_status)
  c(
    "# Joint-QVP Synthetic DGP Forecast Validation Phase 3",
    "",
    "This artifact directory contains registry-driven rolling-origin forecast validation for held-out synthetic DGP test rows.",
    "It consumes Phase 1 fixtures, verifies source hashes, fits AL-VB using only rows available before each forecast origin, and scores one-step-ahead test forecasts.",
    "",
    "This is held-out forecast validation, not Phase 2 train-split fit recovery.",
    "",
    sprintf("- Scenarios: %s", length(unique(run_config$scenario_id))),
    sprintf("- Forecast origins: %s", sum(run_config$n_forecast_origins)),
    sprintf("- Gate counts: %s", paste(paste(names(status_counts), as.integer(status_counts), sep = "="), collapse = ", ")),
    "",
    "Primary files:",
    "",
    "- `run_config.csv`: scenario metadata and fit/forecast controls.",
    "- `fixture_source_manifest.csv`: verified Phase 1 source hashes.",
    "- `forecast_origin_config.csv`: rolling-origin windows and leakage checks.",
    "- `forecast_quantiles_raw.csv`: raw model forecast quantiles before the noncrossing contract.",
    "- `forecast_quantiles.csv`: monotone contract forecast quantiles used for scoring.",
    "- `forecast_monotone_adjustment.csv`: raw-to-contract adjustment diagnostics.",
    "- `raw_crossing_summary.csv`: raw forecast crossing diagnostics.",
    "- `crossing_summary.csv`: contract forecast crossing diagnostics.",
    "- `forecast_truth_comparison.csv`: quantile-path truth distance summaries.",
    "- `pinball_summary.csv`, `hit_rate_summary.csv`, interval/WIS/CRPS summaries: forecast scoring outputs.",
    "- `forecast_validation_assessment.csv`: pass/review/fail gates.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 3 artifacts."
  )
}

app_joint_qvp_phase3_verify_phase2_dir <- function(phase2_dir) {
  if (is.null(phase2_dir) || !nzchar(as.character(phase2_dir))) return(NA)
  phase2_dir <- normalizePath(phase2_dir, mustWork = TRUE)
  manifest_path <- file.path(phase2_dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) stop("phase2_dir was provided but artifact_manifest.csv is missing.", call. = FALSE)
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), "Phase 2 artifact manifest")
  paths <- file.path(phase2_dir, manifest$relative_path)
  exists <- file.exists(paths)
  observed <- rep(NA_character_, length(paths))
  observed[exists] <- vapply(paths[exists], app_sha256_file, character(1L))
  all(exists & observed == manifest$sha256)
}

app_joint_qvp_run_synthetic_dgp_forecast_validation <- function(
  out_dir,
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  fixture_dir = NULL,
  phase2_dir = NULL,
  registry = NULL,
  scenario_ids = NULL,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  alpha_min_spacing = 0,
  vb_max_iter = 80L,
  adaptive_vb_max_iter_grid = c(vb_max_iter, 160L),
  rhs_vb_inner = 5L,
  refit_stride = 1L,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = Inf,
  vb_tol = 1.0e-4
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(fixture_dir)) {
    fixture_dir <- file.path(out_dir, "phase1_fixtures")
    app_joint_qvp_materialize_synthetic_dgp_registry(
      out_dir = fixture_dir,
      registry_path = registry_path,
      registry = registry
    )
  }
  phase2_manifest_verified <- app_joint_qvp_phase3_verify_phase2_dir(phase2_dir)
  tables <- app_joint_qvp_load_phase1_fixture_tables(fixture_dir)
  source_hashes_verified <- all(tables$fixture_source_manifest$hash_verified)
  available_scenario_ids <- tables$scenario_summary$scenario_id
  if (!is.null(scenario_ids)) {
    requested_ids <- unique(as.character(scenario_ids))
    requested_ids <- requested_ids[nzchar(requested_ids)]
    missing_ids <- setdiff(requested_ids, available_scenario_ids)
    if (length(missing_ids)) {
      stop("Requested Phase 3 scenario id(s) are not present in the Phase 1 fixtures: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    scenario_ids <- requested_ids
  } else {
    scenario_ids <- available_scenario_ids
  }
  if (!length(scenario_ids)) stop("No Phase 3 scenarios selected.", call. = FALSE)

  refit_stride <- as.integer(refit_stride)[[1L]]
  if (!is.finite(refit_stride) || refit_stride <= 0L) stop("refit_stride must be a positive integer.", call. = FALSE)
  control_grid <- paste(app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid), collapse = ",")
  fixtures <- lapply(scenario_ids, function(id) app_joint_qvp_phase3_forecast_fixture_from_tables(tables, id))
  names(fixtures) <- scenario_ids

  run_rows <- list()
  origin_rows <- list()
  forecast_rows <- list()
  forecast_raw_rows <- list()
  crossing_rows <- list()
  raw_crossing_rows <- list()
  monotone_adjustment_rows <- list()
  vb_audit_rows <- list()
  objective_rows <- list()
  runtime_rows <- list()

  for (fixture in fixtures) {
    origins <- app_joint_qvp_phase3_origin_rows(
      fixture,
      forecast_origin_stride = forecast_origin_stride,
      max_origins_per_scenario = max_origins_per_scenario
    )
    p <- ncol(fixture$Z)
    K <- length(fixture$tau)
    run_rows[[length(run_rows) + 1L]] <- data.frame(
      scenario_id = fixture$scenario_id,
      scenario_class = fixture$scenario_class,
      distribution_family = fixture$distribution_family,
      dynamics_class = fixture$dynamics_class,
      truth_quantile_method = fixture$truth_quantile_method,
      seed = fixture$seed,
      simulated_length = fixture$simulated_length,
      washout_length = fixture$washout_length,
      train_length = fixture$train_length,
      test_length = fixture$test_length,
      n_forecast_origins = nrow(origins),
      p = p,
      K = K,
      tau_grid = paste(fixture$tau, collapse = ","),
      kappa = kappa,
      tau0 = tau0,
      zeta2 = zeta2,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = if (is.null(alpha_prior_mean)) "none" else paste(as.character(alpha_prior_mean), collapse = ","),
      alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = alpha_min_spacing,
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = control_grid,
      rhs_vb_inner = rhs_vb_inner,
      vb_tol = vb_tol,
      refit_stride = refit_stride,
      forecast_origin_stride = forecast_origin_stride,
      max_origins_per_scenario = if (is.finite(as.numeric(max_origins_per_scenario))) as.integer(max_origins_per_scenario) else NA_integer_,
      phase2_dir = if (is.null(phase2_dir)) NA_character_ else app_prefer_repo_relative_path(phase2_dir),
      phase2_manifest_verified = phase2_manifest_verified,
      source_hashes_verified = source_hashes_verified,
      no_future_test_leakage = all(origins$no_future_test_leakage),
      notes = fixture$notes,
      stringsAsFactors = FALSE
    )

    last_fit <- NULL
    last_fit_origin <- NA_integer_
    last_fit_window <- NULL
    last_vb_adaptive <- NULL
    for (oo in seq_len(nrow(origins))) {
      origin <- origins[oo, , drop = FALSE]
      refit <- is.null(last_fit) || ((origin$origin_index[[1L]] - 1L) %% refit_stride == 0L)
      t0 <- proc.time()[["elapsed"]]
      if (refit) {
        fit_window <- app_joint_qvp_phase3_fit_window(fixture, origin$forecast_time_index[[1L]])
        vb_adaptive <- app_joint_qvp_fit_al_vb_adaptive(
          y = fit_window$y,
          Z = fit_window$Z,
          tau = fixture$tau,
          vb_max_iter = vb_max_iter,
          adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
          tol = vb_tol,
          kappa = kappa,
          tau0 = tau0,
          zeta2 = zeta2,
          a_sigma = a_sigma,
          b_sigma = b_sigma,
          alpha_prior_mean = alpha_prior_mean,
          alpha_prior_sd = alpha_prior_sd,
          alpha_min_spacing = alpha_min_spacing,
          rhs_vb_inner = rhs_vb_inner
        )
        last_fit <- vb_adaptive$fit
        last_fit_origin <- origin$origin_index[[1L]]
        last_fit_window <- fit_window
        last_vb_adaptive <- vb_adaptive
        vb_audit_rows[[length(vb_audit_rows) + 1L]] <- cbind(
          data.frame(
            scenario_id = fixture$scenario_id,
            origin_index = origin$origin_index[[1L]],
            forecast_time_index = origin$forecast_time_index[[1L]],
            refit = TRUE,
            fit_origin_index = origin$origin_index[[1L]],
            stringsAsFactors = FALSE
          ),
          vb_adaptive$audit
        )
      } else {
        vb_audit_rows[[length(vb_audit_rows) + 1L]] <- data.frame(
          scenario_id = fixture$scenario_id,
          origin_index = origin$origin_index[[1L]],
          forecast_time_index = origin$forecast_time_index[[1L]],
          refit = FALSE,
          fit_origin_index = last_fit_origin,
          attempt = NA_integer_,
          max_iter = NA_integer_,
          converged = isTRUE(last_fit$converged),
          status = "reused_fit",
          n_iter = nrow(last_fit$trace),
          final_max_beta_change = tail(last_fit$trace$max_beta_change, 1L),
          objective_status = last_fit$objective_diagnostics$objective_status[[1L]],
          stringsAsFactors = FALSE
        )
      }
      elapsed <- proc.time()[["elapsed"]] - t0
      qhat_raw <- app_joint_qvp_phase3_predict_row(
        last_fit,
        fixture$Z[origin$forecast_retained_pos[[1L]], , drop = FALSE],
        fixture$tau
      )
      forecast_contract <- app_joint_qvp_phase3_contract_forecast(qhat_raw, fixture$tau)
      forecast_raw_rows[[length(forecast_raw_rows) + 1L]] <- app_joint_qvp_phase3_forecast_rows(fixture, origin, forecast_contract$qhat_raw, method = "vb_raw")
      forecast_rows[[length(forecast_rows) + 1L]] <- app_joint_qvp_phase3_forecast_rows(fixture, origin, forecast_contract$qhat_contract, method = "vb")
      monotone_adjustment_rows[[length(monotone_adjustment_rows) + 1L]] <- app_joint_qvp_phase3_monotone_adjustment_row(
        fixture,
        origin,
        forecast_contract,
        method = "vb"
      )
      raw_crossing_rows[[length(raw_crossing_rows) + 1L]] <- cbind(
        data.frame(
          scenario_id = fixture$scenario_id,
          method = "vb_raw",
          origin_index = origin$origin_index[[1L]],
          forecast_time_index = origin$forecast_time_index[[1L]],
          stringsAsFactors = FALSE
        ),
        app_joint_qvp_crossing_diagnostics(matrix(forecast_contract$qhat_raw, nrow = 1L), fixture$tau)
      )
      crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
        data.frame(
          scenario_id = fixture$scenario_id,
          method = "vb",
          origin_index = origin$origin_index[[1L]],
          forecast_time_index = origin$forecast_time_index[[1L]],
          stringsAsFactors = FALSE
        ),
        app_joint_qvp_crossing_diagnostics(matrix(forecast_contract$qhat_contract, nrow = 1L), fixture$tau)
      )
      objective_rows[[length(objective_rows) + 1L]] <- cbind(
        data.frame(
          scenario_id = fixture$scenario_id,
          method = "vb",
          origin_index = origin$origin_index[[1L]],
          forecast_time_index = origin$forecast_time_index[[1L]],
          refit = refit,
          fit_origin_index = last_fit_origin,
          stringsAsFactors = FALSE
        ),
        last_fit$objective_diagnostics
      )
      runtime_rows[[length(runtime_rows) + 1L]] <- data.frame(
        scenario_id = fixture$scenario_id,
        origin_index = origin$origin_index[[1L]],
        forecast_time_index = origin$forecast_time_index[[1L]],
        component = if (refit) "VB adaptive refit" else "VB reused forecast",
        elapsed_sec = elapsed,
        n_iter = if (refit) nrow(last_fit$trace) else 0L,
        sec_per_iter = if (refit) elapsed / max(1L, nrow(last_fit$trace)) else NA_real_,
        stringsAsFactors = FALSE
      )
      used <- last_fit_window$pos
      origin_rows[[length(origin_rows) + 1L]] <- data.frame(
        origins[oo, setdiff(names(origins), "forecast_retained_pos"), drop = FALSE],
        refit = refit,
        fit_origin_index = last_fit_origin,
        used_fit_window_start = min(fixture$time_index[used]),
        used_fit_window_end = max(fixture$time_index[used]),
        used_fit_n = length(used),
        used_train_n = sum(fixture$split[used] == "train"),
        used_previous_test_n = sum(fixture$split[used] == "test"),
        used_fit_max_time_before_forecast = max(fixture$time_index[used]) < origin$forecast_time_index[[1L]],
        vb_status = last_fit$manifest$status[[1L]],
        vb_converged = isTRUE(last_fit$converged),
        vb_n_iter = nrow(last_fit$trace),
        objective_status = last_fit$objective_diagnostics$objective_status[[1L]],
        stringsAsFactors = FALSE
      )
    }
  }

  run_config <- do.call(rbind, run_rows)
  forecast_origin_config <- do.call(rbind, origin_rows)
  forecast_quantiles <- do.call(rbind, forecast_rows)
  forecast_quantiles_raw <- do.call(rbind, forecast_raw_rows)
  forecast_truth_comparison <- app_joint_qvp_phase3_truth_comparison_summary(forecast_quantiles)
  pinball_summary <- app_joint_qvp_phase3_pinball_summary(forecast_quantiles)
  hit_rate_summary <- app_joint_qvp_phase3_hit_rate_summary(forecast_quantiles)
  interval_detail <- app_joint_qvp_phase3_interval_detail(forecast_quantiles)
  interval_coverage_summary <- app_joint_qvp_phase3_interval_coverage_summary(interval_detail)
  interval_score_summary <- app_joint_qvp_phase3_interval_score_summary(interval_detail)
  wis_summary <- app_joint_qvp_phase3_wis_summary(forecast_quantiles, interval_detail)
  crps_grid_summary <- app_joint_qvp_phase3_crps_grid_summary(forecast_quantiles)
  crossing_summary <- do.call(rbind, crossing_rows)
  raw_crossing_summary <- do.call(rbind, raw_crossing_rows)
  forecast_monotone_adjustment <- do.call(rbind, monotone_adjustment_rows)
  vb_convergence_audit <- app_bind_rows_fill(vb_audit_rows)
  objective_diagnostics <- do.call(rbind, objective_rows)
  runtime_summary <- do.call(rbind, runtime_rows)
  forecast_validation_assessment <- app_joint_qvp_phase3_assessment_rows(
    run_config = run_config,
    forecast_quantiles = forecast_quantiles,
    hit_rate_summary = hit_rate_summary,
    crossing_summary = crossing_summary,
    vb_convergence_audit = vb_convergence_audit,
    objective_diagnostics = objective_diagnostics,
    raw_crossing_summary = raw_crossing_summary,
    forecast_monotone_adjustment = forecast_monotone_adjustment,
    source_hashes_verified = source_hashes_verified
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase3_readme_lines(run_config, forecast_validation_assessment), readme_path, useBytes = TRUE)

  fixture_source_manifest <- tables$fixture_source_manifest
  fixture_source_manifest$fixture_dir <- vapply(fixture_source_manifest$fixture_dir, app_prefer_repo_relative_path, character(1L))
  fixture_source_manifest$absolute_path <- vapply(fixture_source_manifest$absolute_path, app_prefer_repo_relative_path, character(1L))

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(fixture_source_manifest, file.path(out_dir, "fixture_source_manifest.csv")),
    forecast_origin_config = app_joint_qvp_write_csv(forecast_origin_config, file.path(out_dir, "forecast_origin_config.csv")),
    forecast_quantiles_raw = app_joint_qvp_write_csv(forecast_quantiles_raw, file.path(out_dir, "forecast_quantiles_raw.csv")),
    forecast_quantiles = app_joint_qvp_write_csv(forecast_quantiles, file.path(out_dir, "forecast_quantiles.csv")),
    forecast_monotone_adjustment = app_joint_qvp_write_csv(forecast_monotone_adjustment, file.path(out_dir, "forecast_monotone_adjustment.csv")),
    forecast_truth_comparison = app_joint_qvp_write_csv(forecast_truth_comparison, file.path(out_dir, "forecast_truth_comparison.csv")),
    pinball_summary = app_joint_qvp_write_csv(pinball_summary, file.path(out_dir, "pinball_summary.csv")),
    hit_rate_summary = app_joint_qvp_write_csv(hit_rate_summary, file.path(out_dir, "hit_rate_summary.csv")),
    interval_coverage_summary = app_joint_qvp_write_csv(interval_coverage_summary, file.path(out_dir, "interval_coverage_summary.csv")),
    interval_score_summary = app_joint_qvp_write_csv(interval_score_summary, file.path(out_dir, "interval_score_summary.csv")),
    wis_summary = app_joint_qvp_write_csv(wis_summary, file.path(out_dir, "wis_summary.csv")),
    crps_grid_summary = app_joint_qvp_write_csv(crps_grid_summary, file.path(out_dir, "crps_grid_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing_summary, file.path(out_dir, "raw_crossing_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence_audit, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective_diagnostics, file.path(out_dir, "objective_diagnostics.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime_summary, file.path(out_dir, "runtime_summary.csv")),
    forecast_validation_assessment = app_joint_qvp_write_csv(forecast_validation_assessment, file.path(out_dir, "forecast_validation_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    fixture_dir = normalizePath(fixture_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    run_config = run_config,
    forecast_origin_config = forecast_origin_config,
    forecast_quantiles = forecast_quantiles,
    forecast_quantiles_raw = forecast_quantiles_raw,
    forecast_monotone_adjustment = forecast_monotone_adjustment,
    forecast_validation_assessment = forecast_validation_assessment
  )
}

app_joint_qvp_default_synthetic_dgp_forecast_calibration_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_20260702")
}

app_joint_qvp_phase4_tier_defaults <- function(tier = c("smoke", "calibration", "article_candidate")) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "calibration", "article_candidate"))
  if (identical(tier, "smoke")) {
    return(list(
      simulated_length = 72L,
      washout_length = 12L,
      train_length = 42L,
      test_length = 18L,
      n_replicates = 1L,
      seed_base = 202607400L,
      vb_max_iter = 8L,
      adaptive_vb_max_iter_grid = 8L,
      refit_stride = 99L,
      forecast_origin_stride = 1L,
      max_origins_per_scenario = 2L,
      min_replicates_for_candidate = 3L,
      min_replicates_for_ready = 10L
    ))
  }
  if (identical(tier, "calibration")) {
    return(list(
      simulated_length = 1200L,
      washout_length = 300L,
      train_length = 500L,
      test_length = 400L,
      n_replicates = 5L,
      seed_base = 202608000L,
      vb_max_iter = 120L,
      adaptive_vb_max_iter_grid = c(120L, 240L),
      refit_stride = 20L,
      forecast_origin_stride = 10L,
      max_origins_per_scenario = 40L,
      min_replicates_for_candidate = 3L,
      min_replicates_for_ready = 10L
    ))
  }
  list(
    simulated_length = 2500L,
    washout_length = 500L,
    train_length = 1000L,
    test_length = 1000L,
    n_replicates = 10L,
    seed_base = 202609000L,
    vb_max_iter = 180L,
    adaptive_vb_max_iter_grid = c(180L, 360L, 500L),
    refit_stride = 30L,
    forecast_origin_stride = 10L,
    max_origins_per_scenario = 100L,
    min_replicates_for_candidate = 3L,
    min_replicates_for_ready = 10L
  )
}

app_joint_qvp_phase4_build_calibration_registry <- function(
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL,
  scenario_ids = NULL,
  tier = c("smoke", "calibration", "article_candidate"),
  n_replicates = NULL,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "calibration", "article_candidate"))
  defaults <- app_joint_qvp_phase4_tier_defaults(tier)
  base <- if (is.null(registry)) app_joint_qvp_load_synthetic_dgp_registry(registry_path) else registry
  app_joint_qvp_validate_synthetic_dgp_registry(base)
  if ("enabled" %in% names(base)) base <- base[app_as_bool_vec(base$enabled), , drop = FALSE]
  if (!is.null(scenario_ids)) {
    scenario_ids <- unique(as.character(scenario_ids))
    scenario_ids <- scenario_ids[nzchar(scenario_ids)]
    missing_ids <- setdiff(scenario_ids, base$scenario_id)
    if (length(missing_ids)) {
      stop("Requested Phase 4 base scenario id(s) not found: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    base <- base[match(scenario_ids, base$scenario_id), , drop = FALSE]
  }
  if (!nrow(base)) stop("No base scenarios selected for Phase 4 calibration.", call. = FALSE)

  n_replicates <- as.integer(n_replicates %||% defaults$n_replicates)
  seed_base <- as.integer(seed_base %||% defaults$seed_base)
  simulated_length <- as.integer(simulated_length %||% defaults$simulated_length)
  washout_length <- as.integer(washout_length %||% defaults$washout_length)
  train_length <- as.integer(train_length %||% defaults$train_length)
  test_length <- as.integer(test_length %||% defaults$test_length)
  if (!is.finite(n_replicates) || n_replicates <= 0L) stop("n_replicates must be positive.", call. = FALSE)
  if (simulated_length != washout_length + train_length + test_length) {
    stop("Phase 4 calibration lengths must satisfy simulated = washout + train + test.", call. = FALSE)
  }

  rows <- list()
  for (ii in seq_len(nrow(base))) {
    base_row <- base[ii, , drop = FALSE]
    base_id <- as.character(base_row$scenario_id[[1L]])
    for (rr in seq_len(n_replicates)) {
      out <- base_row
      out$registry_version <- paste0("phase4_", tier, "_20260702")
      out$scenario_id <- sprintf("%s__%s_r%02d", base_id, tier, rr)
      out$simulated_length <- simulated_length
      out$washout_length <- washout_length
      out$train_length <- train_length
      out$test_length <- test_length
      out$seed <- as.integer(seed_base + ii * 1000L + rr)
      out$base_scenario_id <- base_id
      out$replicate_id <- as.integer(rr)
      out$validation_tier <- tier
      out$seed_role <- sprintf("%s_replicate_seed", tier)
      out$base_seed <- as.integer(base_row$seed[[1L]])
      out$notes <- paste0(as.character(base_row$notes[[1L]]), " Phase 4 ", tier, " replicate ", rr, ".")
      rows[[length(rows) + 1L]] <- out
    }
  }
  out <- app_bind_rows_fill(rows)
  rownames(out) <- NULL
  app_joint_qvp_validate_synthetic_dgp_registry(out)
  out
}

app_joint_qvp_phase4_manifest_with_hashes <- function(dir, manifest_file = "artifact_manifest.csv") {
  manifest_path <- file.path(dir, manifest_file)
  if (!file.exists(manifest_path)) stop(sprintf("Missing artifact manifest: %s", manifest_path), call. = FALSE)
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest, c("label", "relative_path", "size_bytes", "sha256"), "artifact manifest")
  paths <- file.path(dir, manifest$relative_path)
  manifest$artifact_dir <- normalizePath(dir, mustWork = TRUE)
  manifest$absolute_path <- paths
  manifest$file_exists <- file.exists(paths)
  manifest$observed_sha256 <- NA_character_
  manifest$observed_sha256[manifest$file_exists] <- vapply(paths[manifest$file_exists], app_sha256_file, character(1L))
  manifest$hash_verified <- manifest$file_exists & manifest$observed_sha256 == manifest$sha256
  manifest
}

app_joint_qvp_phase4_metric_summary <- function(values) {
  values <- as.numeric(values)
  finite <- values[is.finite(values)]
  if (!length(finite)) {
    return(data.frame(
      n = length(values), finite_n = 0L, min = NA_real_, q25 = NA_real_, median = NA_real_,
      mean = NA_real_, q90 = NA_real_, q95 = NA_real_, max = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    n = length(values),
    finite_n = length(finite),
    min = min(finite),
    q25 = as.numeric(stats::quantile(finite, 0.25, names = FALSE, type = 8)),
    median = stats::median(finite),
    mean = mean(finite),
    q90 = as.numeric(stats::quantile(finite, 0.90, names = FALSE, type = 8)),
    q95 = as.numeric(stats::quantile(finite, 0.95, names = FALSE, type = 8)),
    max = max(finite),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4_add_registry_meta <- function(x, registry) {
  meta_cols <- c(
    "scenario_id", "base_scenario_id", "replicate_id", "validation_tier",
    "seed_role", "scenario_class", "distribution_family", "dynamics_class"
  )
  meta <- registry[, intersect(meta_cols, names(registry)), drop = FALSE]
  merge(x, meta, by = "scenario_id", all.x = TRUE, sort = FALSE)
}

app_joint_qvp_phase4_metric_long <- function(
  calibration_registry,
  forecast_truth_comparison,
  pinball_summary,
  hit_rate_summary,
  interval_coverage_summary,
  interval_score_summary,
  wis_summary,
  crps_grid_summary,
  crossing_summary,
  runtime_summary,
  assessment
) {
  rows <- list()
  add_rows <- function(df, metric, value, extra_cols = character()) {
    if (!nrow(df)) return(NULL)
    keep <- unique(c("scenario_id", extra_cols))
    keep <- keep[keep %in% names(df)]
    out <- df[, keep, drop = FALSE]
    out$metric <- metric
    out$value <- as.numeric(value)
    rows[[length(rows) + 1L]] <<- app_joint_qvp_phase4_add_registry_meta(out, calibration_registry)
    invisible(NULL)
  }
  add_rows(assessment, "truth_normalized_qhat_distance", assessment$truth_normalized_qhat_distance)
  add_rows(forecast_truth_comparison, "rmse_to_truth", forecast_truth_comparison$rmse_to_truth, c("method", "quantile_index", "tau"))
  add_rows(forecast_truth_comparison, "mae_to_truth", forecast_truth_comparison$mae_to_truth, c("method", "quantile_index", "tau"))
  add_rows(forecast_truth_comparison, "abs_bias_to_truth", abs(forecast_truth_comparison$bias_to_truth), c("method", "quantile_index", "tau"))
  add_rows(pinball_summary, "pinball_mean", pinball_summary$pinball_mean, c("method", "quantile_index", "tau"))
  add_rows(hit_rate_summary, "abs_hit_rate_error", abs(hit_rate_summary$hit_rate_minus_tau), c("method", "quantile_index", "tau"))
  add_rows(interval_coverage_summary, "abs_interval_coverage_error", abs(interval_coverage_summary$coverage_minus_nominal), c("method", "lower_tau", "upper_tau", "nominal"))
  add_rows(interval_score_summary, "interval_width_mean", interval_score_summary$interval_width_mean, c("method", "lower_tau", "upper_tau", "nominal"))
  add_rows(interval_score_summary, "interval_score_mean", interval_score_summary$interval_score_mean, c("method", "lower_tau", "upper_tau", "nominal"))
  add_rows(wis_summary, "wis_mean", wis_summary$wis_mean, c("method"))
  add_rows(crps_grid_summary, "crps_grid_mean", crps_grid_summary$crps_grid_mean, c("method"))
  crossing_by_scenario <- aggregate(n_crossing_pairs ~ scenario_id, crossing_summary, sum)
  add_rows(crossing_by_scenario, "total_crossing_pairs", crossing_by_scenario$n_crossing_pairs)
  if (!length(rows)) return(data.frame())
  app_bind_rows_fill(rows)
}

app_joint_qvp_phase4_distribution_summary <- function(metric_long, group_cols = character()) {
  if (!nrow(metric_long)) return(data.frame())
  group_cols <- group_cols[group_cols %in% names(metric_long)]
  key_cols <- c(group_cols, "metric")
  keys <- unique(metric_long[, key_cols, drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- rep(TRUE, nrow(metric_long))
    for (col in key_cols) {
      key_value <- keys[[col]][[ii]]
      idx <- idx & if (is.na(key_value)) is.na(metric_long[[col]]) else metric_long[[col]] == key_value
    }
    rows[[ii]] <- cbind(keys[ii, , drop = FALSE], app_joint_qvp_phase4_metric_summary(metric_long$value[idx]))
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase4_metric_by_scenario_summary <- function(
  calibration_registry,
  assessment,
  metric_long,
  crossing_summary,
  vb_convergence_audit,
  objective_diagnostics,
  runtime_summary
) {
  scenarios <- unique(calibration_registry$scenario_id)
  rows <- vector("list", length(scenarios))
  for (ii in seq_along(scenarios)) {
    scenario_id <- scenarios[[ii]]
    reg <- calibration_registry[calibration_registry$scenario_id == scenario_id, , drop = FALSE]
    assess <- assessment[assessment$scenario_id == scenario_id, , drop = FALSE]
    m <- metric_long[metric_long$scenario_id == scenario_id, , drop = FALSE]
    metric_value <- function(metric) {
      vals <- m$value[m$metric == metric]
      if (length(vals) && any(is.finite(vals))) mean(vals, na.rm = TRUE) else NA_real_
    }
    refit <- vb_convergence_audit[vb_convergence_audit$scenario_id == scenario_id & app_as_bool_vec(vb_convergence_audit$refit), , drop = FALSE]
    runtime <- runtime_summary[runtime_summary$scenario_id == scenario_id, , drop = FALSE]
    objective <- objective_diagnostics[objective_diagnostics$scenario_id == scenario_id, , drop = FALSE]
    crossing <- crossing_summary[crossing_summary$scenario_id == scenario_id, , drop = FALSE]
    rows[[ii]] <- data.frame(
      scenario_id = scenario_id,
      base_scenario_id = reg$base_scenario_id[[1L]] %||% scenario_id,
      replicate_id = as.integer(reg$replicate_id[[1L]] %||% NA_integer_),
      validation_tier = reg$validation_tier[[1L]] %||% NA_character_,
      scenario_class = reg$scenario_class[[1L]],
      distribution_family = reg$distribution_family[[1L]],
      dynamics_class = reg$dynamics_class[[1L]],
      gate_status = if (nrow(assess)) assess$gate_status[[1L]] else NA_character_,
      implementation_status = if (nrow(assess)) assess$implementation_status[[1L]] else NA_character_,
      truth_normalized_qhat_distance = metric_value("truth_normalized_qhat_distance"),
      rmse_to_truth_mean = metric_value("rmse_to_truth"),
      mae_to_truth_mean = metric_value("mae_to_truth"),
      pinball_mean = metric_value("pinball_mean"),
      abs_hit_rate_error_mean = metric_value("abs_hit_rate_error"),
      abs_interval_coverage_error_mean = metric_value("abs_interval_coverage_error"),
      wis_mean = metric_value("wis_mean"),
      crps_grid_mean = metric_value("crps_grid_mean"),
      total_crossing_pairs = if (nrow(crossing)) sum(crossing$n_crossing_pairs) else NA_real_,
      vb_refit_count = nrow(refit),
      vb_max_iter_count = if (nrow(refit)) sum(as.character(refit$status) != "prototype_success") else 0L,
      vb_max_iter_rate = if (nrow(refit)) mean(as.character(refit$status) != "prototype_success") else NA_real_,
      objective_review_rate = if (nrow(objective)) mean(as.character(objective$objective_status) != "pass") else NA_real_,
      runtime_total_sec = if (nrow(runtime)) sum(runtime$elapsed_sec) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase4_interval_metric_summary <- function(interval_coverage_summary, interval_score_summary, calibration_registry) {
  cov <- interval_coverage_summary
  score <- interval_score_summary
  if (!nrow(cov) && !nrow(score)) return(data.frame())
  merged <- merge(
    cov,
    score,
    by = intersect(c("scenario_id", "method", "lower_tau", "upper_tau", "nominal"), intersect(names(cov), names(score))),
    all = TRUE,
    sort = FALSE
  )
  merged$abs_coverage_error <- abs(merged$coverage_minus_nominal)
  app_joint_qvp_phase4_add_registry_meta(merged, calibration_registry)
}

app_joint_qvp_phase4_vb_convergence_summary <- function(vb_convergence_audit, calibration_registry) {
  scenarios <- unique(vb_convergence_audit$scenario_id)
  rows <- vector("list", length(scenarios))
  for (ii in seq_along(scenarios)) {
    scenario_id <- scenarios[[ii]]
    block <- vb_convergence_audit[vb_convergence_audit$scenario_id == scenario_id, , drop = FALSE]
    refit <- block[app_as_bool_vec(block$refit), , drop = FALSE]
    rows[[ii]] <- data.frame(
      scenario_id = scenario_id,
      n_audit_rows = nrow(block),
      n_refit_rows = nrow(refit),
      n_reused_rows = sum(!app_as_bool_vec(block$refit)),
      n_max_iter = if (nrow(refit)) sum(as.character(refit$status) != "prototype_success") else 0L,
      max_iter_rate = if (nrow(refit)) mean(as.character(refit$status) != "prototype_success") else NA_real_,
      objective_review_rate = if (nrow(block)) mean(as.character(block$objective_status) != "pass") else NA_real_,
      max_n_iter = if (nrow(block)) max(block$n_iter, na.rm = TRUE) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
  app_joint_qvp_phase4_add_registry_meta(do.call(rbind, rows), calibration_registry)
}

app_joint_qvp_phase4_runtime_summary <- function(runtime_summary, calibration_registry) {
  scenarios <- unique(runtime_summary$scenario_id)
  rows <- vector("list", length(scenarios))
  for (ii in seq_along(scenarios)) {
    scenario_id <- scenarios[[ii]]
    block <- runtime_summary[runtime_summary$scenario_id == scenario_id, , drop = FALSE]
    rows[[ii]] <- data.frame(
      scenario_id = scenario_id,
      n_runtime_rows = nrow(block),
      runtime_total_sec = sum(block$elapsed_sec),
      runtime_mean_sec = mean(block$elapsed_sec),
      runtime_max_sec = max(block$elapsed_sec),
      refit_runtime_sec = sum(block$elapsed_sec[block$component == "VB adaptive refit"]),
      forecast_runtime_sec = sum(block$elapsed_sec[block$component != "VB adaptive refit"]),
      stringsAsFactors = FALSE
    )
  }
  app_joint_qvp_phase4_add_registry_meta(do.call(rbind, rows), calibration_registry)
}

app_joint_qvp_phase4_threshold_status <- function(n_replicates, calibration_n, min_candidate, min_ready) {
  if (n_replicates >= min_ready && calibration_n >= 50L) return("ready_for_article_candidate")
  if (n_replicates >= min_candidate && calibration_n >= 20L) return("candidate")
  "needs_more_calibration"
}

app_joint_qvp_phase4_threshold_rows <- function(
  metric_summary,
  n_replicates,
  min_candidate,
  min_ready,
  pass_quantile = 0.90,
  review_quantile = 0.95
) {
  wanted <- c(
    "truth_normalized_qhat_distance",
    "rmse_to_truth",
    "mae_to_truth",
    "abs_bias_to_truth",
    "pinball_mean",
    "abs_hit_rate_error",
    "abs_interval_coverage_error",
    "interval_width_mean",
    "interval_score_mean",
    "wis_mean",
    "crps_grid_mean"
  )
  rows <- list()
  for (metric in wanted) {
    block <- metric_summary[metric_summary$metric == metric, , drop = FALSE]
    if (!nrow(block)) next
    pass <- block$q90[[1L]]
    review <- block$q95[[1L]]
    if (metric %in% c("abs_hit_rate_error", "abs_interval_coverage_error")) {
      pass <- min(1, max(0.05, pass))
      review <- min(1, max(pass, review))
    }
    if (metric == "truth_normalized_qhat_distance") {
      pass <- max(0.25, pass)
      review <- max(pass, review)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      threshold_name = paste0(metric, "_global_q", as.integer(pass_quantile * 100)),
      metric = metric,
      scope = "global",
      recommended_pass_threshold = pass,
      recommended_review_threshold = review,
      calibration_quantile_used = pass_quantile,
      calibration_n = block$finite_n[[1L]],
      rationale = sprintf("Global %s quantile from Phase 4 calibration with conservative finite-metric safeguards.", pass_quantile),
      status = app_joint_qvp_phase4_threshold_status(n_replicates, block$finite_n[[1L]], min_candidate, min_ready),
      stringsAsFactors = FALSE
    )
  }
  rows[[length(rows) + 1L]] <- data.frame(
    threshold_name = "total_crossing_pairs_global_hard_fail",
    metric = "total_crossing_pairs",
    scope = "global",
    recommended_pass_threshold = 0,
    recommended_review_threshold = 0,
    calibration_quantile_used = NA_real_,
    calibration_n = if ("total_crossing_pairs" %in% metric_summary$metric) {
      metric_summary$finite_n[metric_summary$metric == "total_crossing_pairs"][[1L]]
    } else {
      0L
    },
    rationale = "Forecast quantile crossings remain a hard implementation gate; any positive crossing count fails.",
    status = "ready_for_article_candidate",
    stringsAsFactors = FALSE
  )
  do.call(rbind, rows)
}

app_joint_qvp_phase4_assessment_rows <- function(
  calibration_registry,
  phase3_manifest,
  phase3_run_config,
  forecast_quantiles,
  crossing_summary,
  forecast_calibrated_thresholds,
  vb_convergence_calibration_summary,
  runtime_calibration_summary,
  n_replicates,
  min_candidate_replicates = 3L,
  vb_max_iter_review_fraction = 0.25
) {
  manifest_ok <- nrow(phase3_manifest) > 0L && all(phase3_manifest$hash_verified)
  registry_ok <- tryCatch({
    app_joint_qvp_validate_synthetic_dgp_registry(calibration_registry)
    TRUE
  }, error = function(e) FALSE)
  leakage_ok <- nrow(phase3_run_config) > 0L && all(app_as_bool_vec(phase3_run_config$no_future_test_leakage))
  finite_ok <- nrow(forecast_quantiles) > 0L &&
    all(is.finite(forecast_quantiles$qhat)) &&
    all(is.finite(forecast_quantiles$pinball_loss)) &&
    all(is.finite(forecast_quantiles$true_quantile))
  crossing_total <- if (nrow(crossing_summary)) sum(crossing_summary$n_crossing_pairs) else NA_real_
  crossing_ok <- is.finite(crossing_total) && crossing_total == 0
  threshold_ok <- nrow(forecast_calibrated_thresholds) > 0L &&
    all(is.finite(forecast_calibrated_thresholds$recommended_pass_threshold)) &&
    all(nzchar(forecast_calibrated_thresholds$rationale))
  provenance_ok <- file.exists(file.path(dirname(phase3_manifest$artifact_dir[[1L]]), "provenance.csv")) ||
    "provenance" %in% phase3_manifest$label
  hard_fail <- !manifest_ok || !registry_ok || !leakage_ok || !finite_ok || !crossing_ok || !threshold_ok || !provenance_ok
  max_iter_rate <- if (nrow(vb_convergence_calibration_summary)) {
    mean(vb_convergence_calibration_summary$max_iter_rate, na.rm = TRUE)
  } else {
    NA_real_
  }
  runtime_outlier <- FALSE
  if (nrow(runtime_calibration_summary) > 2L) {
    med_runtime <- stats::median(runtime_calibration_summary$runtime_total_sec, na.rm = TRUE)
    runtime_outlier <- is.finite(med_runtime) && med_runtime > 0 &&
      max(runtime_calibration_summary$runtime_total_sec, na.rm = TRUE) > 10 * med_runtime
  }
  too_few_reps <- n_replicates < min_candidate_replicates
  threshold_review <- any(forecast_calibrated_thresholds$status == "needs_more_calibration")
  vb_review <- is.finite(max_iter_rate) && max_iter_rate > vb_max_iter_review_fraction
  review <- too_few_reps || threshold_review || vb_review || runtime_outlier
  data.frame(
    scope = "phase4_forecast_calibration",
    implementation_status = if (hard_fail) "fail" else "pass",
    threshold_support_status = if (threshold_review || too_few_reps) "review" else "pass",
    vb_convergence_status = if (vb_review) "review" else "pass",
    runtime_status = if (runtime_outlier) "review" else "pass",
    gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    n_registry_rows = nrow(calibration_registry),
    n_replicates = n_replicates,
    n_phase3_artifacts = nrow(phase3_manifest),
    phase3_manifest_hashes_verified = manifest_ok,
    no_future_test_leakage = leakage_ok,
    finite_forecasts_and_scores = finite_ok,
    total_crossing_pairs = crossing_total,
    threshold_rows = nrow(forecast_calibrated_thresholds),
    mean_vb_max_iter_rate = max_iter_rate,
    note = app_joint_qvp_ts_assessment_note(c(
      if (!manifest_ok) "missing or unverifiable Phase 3 artifact hashes",
      if (!registry_ok) "malformed calibration registry",
      if (!leakage_ok) "train/test leakage",
      if (!finite_ok) "nonfinite forecast quantiles or scores",
      if (!crossing_ok) "forecast quantile crossings",
      if (!threshold_ok) "missing or nonfinite threshold table",
      if (!provenance_ok) "missing provenance",
      if (too_few_reps) "too few calibration replicates",
      if (threshold_review) "thresholds need more calibration",
      if (vb_review) "VB max-iteration review",
      if (runtime_outlier) "runtime outlier review"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4_article_candidate_run_plan <- function(
  base_registry,
  seed_base,
  scenario_ids = NULL
) {
  defaults <- app_joint_qvp_phase4_tier_defaults("article_candidate")
  base <- base_registry
  if ("enabled" %in% names(base)) base <- base[app_as_bool_vec(base$enabled), , drop = FALSE]
  if (!is.null(scenario_ids)) base <- base[base$scenario_id %in% scenario_ids, , drop = FALSE]
  data.frame(
    base_scenario_id = base$scenario_id,
    validation_tier = "article_candidate",
    recommended_n_replicates = defaults$n_replicates,
    seed_base = as.integer(seed_base),
    simulated_length = defaults$simulated_length,
    washout_length = defaults$washout_length,
    train_length = defaults$train_length,
    test_length = defaults$test_length,
    vb_max_iter = defaults$vb_max_iter,
    adaptive_vb_max_iter_grid = paste(defaults$adaptive_vb_max_iter_grid, collapse = ","),
    refit_stride = defaults$refit_stride,
    forecast_origin_stride = defaults$forecast_origin_stride,
    max_origins_per_scenario = defaults$max_origins_per_scenario,
    status = "planned_not_run",
    rationale = "Article-candidate plan uses separate seeds and larger train/test windows after Phase 4 calibration readiness.",
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4_readme_lines <- function(run_config, assessment, thresholds) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Calibration Phase 4",
    "",
    "This artifact directory contains calibration/readiness evidence for the registry-driven joint-QVP synthetic forecast study.",
    "It generates a replicated calibration registry, runs Phase 3 forecast validation, summarizes metric distributions, and proposes conservative threshold candidates.",
    "",
    "This is not final article evidence. It is the calibration layer before article-candidate validation outputs are frozen.",
    "",
    sprintf("- Tier: %s", unique(run_config$validation_tier)[[1L]]),
    sprintf("- Calibration registry rows: %s", run_config$n_registry_rows[[1L]]),
    sprintf("- Replicates per base scenario: %s", run_config$n_replicates[[1L]]),
    sprintf("- Phase 4 gate: %s", assessment$gate_status[[1L]]),
    sprintf("- Threshold rows: %s", nrow(thresholds)),
    "",
    "Primary files:",
    "",
    "- `calibration_registry.csv`: replicated registry used for calibration fixtures.",
    "- `calibration_run_config.csv`: tier, seed, size, VB, refit, and Phase 3 artifact controls.",
    "- `phase3_artifact_manifest.csv`: verified hashes for the underlying Phase 3 run.",
    "- `forecast_metric_*summary.csv`: metric distribution summaries across scenarios, families, and taus.",
    "- `forecast_calibrated_thresholds.csv`: provisional threshold candidates with rationale.",
    "- `forecast_calibration_assessment.csv`: pass/review/fail readiness gates.",
    "- `article_candidate_run_plan.csv`: suggested heavier article-candidate run controls.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 4 artifacts."
  )
}

app_joint_qvp_run_synthetic_dgp_forecast_calibration <- function(
  out_dir,
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL,
  scenario_ids = NULL,
  tier = c("smoke", "calibration", "article_candidate"),
  n_replicates = NULL,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL,
  vb_max_iter = NULL,
  adaptive_vb_max_iter_grid = NULL,
  refit_stride = NULL,
  forecast_origin_stride = NULL,
  max_origins_per_scenario = NULL
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "calibration", "article_candidate"))
  defaults <- app_joint_qvp_phase4_tier_defaults(tier)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  base_registry <- if (is.null(registry)) app_joint_qvp_load_synthetic_dgp_registry(registry_path) else registry
  n_replicates <- as.integer(n_replicates %||% defaults$n_replicates)
  seed_base <- as.integer(seed_base %||% defaults$seed_base)
  simulated_length <- as.integer(simulated_length %||% defaults$simulated_length)
  washout_length <- as.integer(washout_length %||% defaults$washout_length)
  train_length <- as.integer(train_length %||% defaults$train_length)
  test_length <- as.integer(test_length %||% defaults$test_length)
  vb_max_iter <- as.integer(vb_max_iter %||% defaults$vb_max_iter)
  adaptive_vb_max_iter_grid <- adaptive_vb_max_iter_grid %||% defaults$adaptive_vb_max_iter_grid
  refit_stride <- as.integer(refit_stride %||% defaults$refit_stride)
  forecast_origin_stride <- as.integer(forecast_origin_stride %||% defaults$forecast_origin_stride)
  max_origins_per_scenario <- max_origins_per_scenario %||% defaults$max_origins_per_scenario

  calibration_registry <- app_joint_qvp_phase4_build_calibration_registry(
    registry = base_registry,
    scenario_ids = scenario_ids,
    tier = tier,
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length
  )
  phase3_dir <- file.path(out_dir, "phase3_forecast_validation")
  phase3_result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
    out_dir = phase3_dir,
    registry = calibration_registry,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = max_origins_per_scenario
  )
  phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_result$out_dir)
  phase3_manifest$artifact_dir <- vapply(phase3_manifest$artifact_dir, app_prefer_repo_relative_path, character(1L))
  phase3_manifest$absolute_path <- vapply(phase3_manifest$absolute_path, app_prefer_repo_relative_path, character(1L))

  read_phase3 <- function(name) app_read_csv(file.path(phase3_result$out_dir, name))
  phase3_run_config <- read_phase3("run_config.csv")
  forecast_truth_comparison <- read_phase3("forecast_truth_comparison.csv")
  pinball_summary <- read_phase3("pinball_summary.csv")
  hit_rate_summary <- read_phase3("hit_rate_summary.csv")
  interval_coverage_summary <- read_phase3("interval_coverage_summary.csv")
  interval_score_summary <- read_phase3("interval_score_summary.csv")
  wis_summary <- read_phase3("wis_summary.csv")
  crps_grid_summary <- read_phase3("crps_grid_summary.csv")
  crossing_summary <- read_phase3("crossing_summary.csv")
  vb_convergence_audit <- read_phase3("vb_convergence_audit.csv")
  objective_diagnostics <- read_phase3("objective_diagnostics.csv")
  runtime_summary <- read_phase3("runtime_summary.csv")
  forecast_quantiles <- read_phase3("forecast_quantiles.csv")
  phase3_assessment <- read_phase3("forecast_validation_assessment.csv")

  metric_long <- app_joint_qvp_phase4_metric_long(
    calibration_registry = calibration_registry,
    forecast_truth_comparison = forecast_truth_comparison,
    pinball_summary = pinball_summary,
    hit_rate_summary = hit_rate_summary,
    interval_coverage_summary = interval_coverage_summary,
    interval_score_summary = interval_score_summary,
    wis_summary = wis_summary,
    crps_grid_summary = crps_grid_summary,
    crossing_summary = crossing_summary,
    runtime_summary = runtime_summary,
    assessment = phase3_assessment
  )
  forecast_metric_distribution_summary <- app_joint_qvp_phase4_distribution_summary(metric_long)
  forecast_metric_by_family_summary <- app_joint_qvp_phase4_distribution_summary(metric_long, c("distribution_family"))
  tau_metric_long <- if ("tau" %in% names(metric_long)) {
    metric_long[is.finite(metric_long$tau), , drop = FALSE]
  } else {
    metric_long[FALSE, , drop = FALSE]
  }
  forecast_metric_by_tau_summary <- app_joint_qvp_phase4_distribution_summary(tau_metric_long, c("tau"))
  forecast_metric_by_scenario_summary <- app_joint_qvp_phase4_metric_by_scenario_summary(
    calibration_registry = calibration_registry,
    assessment = phase3_assessment,
    metric_long = metric_long,
    crossing_summary = crossing_summary,
    vb_convergence_audit = vb_convergence_audit,
    objective_diagnostics = objective_diagnostics,
    runtime_summary = runtime_summary
  )
  interval_metric_summary <- app_joint_qvp_phase4_interval_metric_summary(
    interval_coverage_summary,
    interval_score_summary,
    calibration_registry
  )
  vb_convergence_calibration_summary <- app_joint_qvp_phase4_vb_convergence_summary(vb_convergence_audit, calibration_registry)
  runtime_calibration_summary <- app_joint_qvp_phase4_runtime_summary(runtime_summary, calibration_registry)
  forecast_calibrated_thresholds <- app_joint_qvp_phase4_threshold_rows(
    metric_summary = forecast_metric_distribution_summary,
    n_replicates = n_replicates,
    min_candidate = defaults$min_replicates_for_candidate,
    min_ready = defaults$min_replicates_for_ready
  )
  forecast_calibration_assessment <- app_joint_qvp_phase4_assessment_rows(
    calibration_registry = calibration_registry,
    phase3_manifest = phase3_manifest,
    phase3_run_config = phase3_run_config,
    forecast_quantiles = forecast_quantiles,
    crossing_summary = crossing_summary,
    forecast_calibrated_thresholds = forecast_calibrated_thresholds,
    vb_convergence_calibration_summary = vb_convergence_calibration_summary,
    runtime_calibration_summary = runtime_calibration_summary,
    n_replicates = n_replicates,
    min_candidate_replicates = defaults$min_replicates_for_candidate
  )
  article_candidate_run_plan <- app_joint_qvp_phase4_article_candidate_run_plan(
    base_registry = base_registry,
    seed_base = seed_base + 100000L,
    scenario_ids = scenario_ids
  )
  calibration_run_config <- data.frame(
    validation_tier = tier,
    n_registry_rows = nrow(calibration_registry),
    n_base_scenarios = length(unique(calibration_registry$base_scenario_id)),
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid), collapse = ","),
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = if (is.finite(as.numeric(max_origins_per_scenario))) as.integer(max_origins_per_scenario) else NA_integer_,
    phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
    phase3_artifact_manifest = app_prefer_repo_relative_path(phase3_result$paths[["artifact_manifest"]]),
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(
    app_joint_qvp_phase4_readme_lines(calibration_run_config, forecast_calibration_assessment, forecast_calibrated_thresholds),
    readme_path,
    useBytes = TRUE
  )
  paths <- c(
    calibration_registry = app_joint_qvp_write_csv(calibration_registry, file.path(out_dir, "calibration_registry.csv")),
    calibration_run_config = app_joint_qvp_write_csv(calibration_run_config, file.path(out_dir, "calibration_run_config.csv")),
    phase3_artifact_manifest = app_joint_qvp_write_csv(phase3_manifest, file.path(out_dir, "phase3_artifact_manifest.csv")),
    forecast_metric_distribution_summary = app_joint_qvp_write_csv(forecast_metric_distribution_summary, file.path(out_dir, "forecast_metric_distribution_summary.csv")),
    forecast_metric_by_scenario_summary = app_joint_qvp_write_csv(forecast_metric_by_scenario_summary, file.path(out_dir, "forecast_metric_by_scenario_summary.csv")),
    forecast_metric_by_family_summary = app_joint_qvp_write_csv(forecast_metric_by_family_summary, file.path(out_dir, "forecast_metric_by_family_summary.csv")),
    forecast_metric_by_tau_summary = app_joint_qvp_write_csv(forecast_metric_by_tau_summary, file.path(out_dir, "forecast_metric_by_tau_summary.csv")),
    interval_metric_summary = app_joint_qvp_write_csv(interval_metric_summary, file.path(out_dir, "interval_metric_summary.csv")),
    vb_convergence_calibration_summary = app_joint_qvp_write_csv(vb_convergence_calibration_summary, file.path(out_dir, "vb_convergence_calibration_summary.csv")),
    runtime_calibration_summary = app_joint_qvp_write_csv(runtime_calibration_summary, file.path(out_dir, "runtime_calibration_summary.csv")),
    forecast_calibrated_thresholds = app_joint_qvp_write_csv(forecast_calibrated_thresholds, file.path(out_dir, "forecast_calibrated_thresholds.csv")),
    forecast_calibration_assessment = app_joint_qvp_write_csv(forecast_calibration_assessment, file.path(out_dir, "forecast_calibration_assessment.csv")),
    article_candidate_run_plan = app_joint_qvp_write_csv(article_candidate_run_plan, file.path(out_dir, "article_candidate_run_plan.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    phase3_out_dir = phase3_result$out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    calibration_registry = calibration_registry,
    calibration_run_config = calibration_run_config,
    forecast_calibrated_thresholds = forecast_calibrated_thresholds,
    forecast_calibration_assessment = forecast_calibration_assessment
  )
}

app_joint_qvp_default_synthetic_dgp_forecast_calibration_readiness_dir <- function(phase4_dir) {
  file.path(phase4_dir, "phase4b_readiness_audit")
}

app_joint_qvp_phase4b_read_required <- function(dir, filename, required_cols) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) stop(sprintf("Missing required Phase 4b input: %s", path), call. = FALSE)
  out <- app_read_csv(path)
  app_check_required_columns(out, required_cols, filename)
  out
}

app_joint_qvp_phase4b_read_optional <- function(dir, filename, required_cols, default = data.frame()) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) return(default)
  out <- app_read_csv(path)
  app_check_required_columns(out, required_cols, filename)
  out
}

app_joint_qvp_phase4b_status <- function(hard_fail, review) {
  if (isTRUE(hard_fail)) return("fail")
  if (isTRUE(review)) return("review")
  "pass"
}

app_joint_qvp_phase4b_count_status <- function(x, value) {
  sum(as.character(x) == value, na.rm = TRUE)
}

app_joint_qvp_phase4b_recommended_article_command <- function(
  article_candidate_run_plan,
  output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_article_candidate_20260702")
) {
  if (!nrow(article_candidate_run_plan)) return(NA_character_)
  plan <- article_candidate_run_plan[1L, , drop = FALSE]
  paste(
    "Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R",
    "--tier article_candidate",
    sprintf("--output-dir %s", output_dir),
    sprintf("--n-replicates %s", plan$recommended_n_replicates[[1L]]),
    sprintf("--seed-base %s", plan$seed_base[[1L]]),
    sprintf("--simulated-length %s", plan$simulated_length[[1L]]),
    sprintf("--washout-length %s", plan$washout_length[[1L]]),
    sprintf("--train-length %s", plan$train_length[[1L]]),
    sprintf("--test-length %s", plan$test_length[[1L]]),
    sprintf("--vb-max-iter %s", plan$vb_max_iter[[1L]]),
    sprintf("--adaptive-vb-max-iter-grid %s", plan$adaptive_vb_max_iter_grid[[1L]]),
    sprintf("--refit-stride %s", plan$refit_stride[[1L]]),
    sprintf("--forecast-origin-stride %s", plan$forecast_origin_stride[[1L]]),
    sprintf("--max-origins-per-scenario %s", plan$max_origins_per_scenario[[1L]])
  )
}

app_joint_qvp_phase4b_recommended_calibration_command <- function(
  output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_followup_20260702")
) {
  paste(
    "Rscript application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R",
    "--tier calibration",
    sprintf("--output-dir %s", output_dir),
    "--n-replicates 5",
    "--vb-max-iter 240",
    "--adaptive-vb-max-iter-grid 240,360",
    "--refit-stride 20",
    "--forecast-origin-stride 10",
    "--max-origins-per-scenario 40"
  )
}

app_joint_qvp_phase4b_load_artifacts <- function(phase4_dir) {
  phase4_dir <- normalizePath(phase4_dir, mustWork = TRUE)
  phase4_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase4_dir)
  calibration_registry <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "calibration_registry.csv",
    c("scenario_id", "base_scenario_id", "replicate_id", "validation_tier")
  )
  calibration_run_config <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "calibration_run_config.csv",
    c("validation_tier", "n_registry_rows", "n_replicates", "phase3_out_dir")
  )
  phase3_recorded_manifest <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "phase3_artifact_manifest.csv",
    c("label", "relative_path", "sha256", "file_exists", "hash_verified")
  )
  forecast_metric_distribution_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "forecast_metric_distribution_summary.csv",
    c("metric", "n", "finite_n", "q90", "q95")
  )
  forecast_metric_by_scenario_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "forecast_metric_by_scenario_summary.csv",
    c("scenario_id", "base_scenario_id", "gate_status", "implementation_status", "runtime_total_sec")
  )
  forecast_metric_by_family_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "forecast_metric_by_family_summary.csv",
    c("distribution_family", "metric", "finite_n", "q90", "q95")
  )
  forecast_metric_by_tau_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "forecast_metric_by_tau_summary.csv",
    c("tau", "metric", "finite_n", "q90", "q95")
  )
  interval_metric_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "interval_metric_summary.csv",
    c("scenario_id", "lower_tau", "upper_tau", "abs_coverage_error")
  )
  vb_convergence_calibration_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "vb_convergence_calibration_summary.csv",
    c("scenario_id", "max_iter_rate", "objective_review_rate")
  )
  runtime_calibration_summary <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "runtime_calibration_summary.csv",
    c("scenario_id", "runtime_total_sec", "refit_runtime_sec")
  )
  forecast_calibrated_thresholds <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "forecast_calibrated_thresholds.csv",
    c("threshold_name", "metric", "recommended_pass_threshold", "rationale", "status")
  )
  forecast_calibration_assessment <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "forecast_calibration_assessment.csv",
    c("scope", "implementation_status", "gate_status", "threshold_rows")
  )
  article_candidate_run_plan <- app_joint_qvp_phase4b_read_required(
    phase4_dir,
    "article_candidate_run_plan.csv",
    c("base_scenario_id", "recommended_n_replicates", "seed_base", "status", "rationale")
  )

  phase3_dir <- file.path(phase4_dir, "phase3_forecast_validation")
  if (!dir.exists(phase3_dir)) {
    phase3_out_dir <- as.character(calibration_run_config$phase3_out_dir[[1L]])
    phase3_dir <- if (grepl("^/", phase3_out_dir)) phase3_out_dir else app_path(phase3_out_dir)
  }
  phase3_dir <- normalizePath(phase3_dir, mustWork = TRUE)
  phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_dir)
  phase3_run_config <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "run_config.csv",
    c("scenario_id", "n_forecast_origins", "no_future_test_leakage")
  )
  phase3_assessment <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "forecast_validation_assessment.csv",
    c("scenario_id", "implementation_status", "gate_status", "total_crossing_pairs", "note")
  )
  phase3_forecast_quantiles <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "forecast_quantiles.csv",
    c("scenario_id", "origin_index", "tau", "qhat", "true_quantile", "pinball_loss")
  )
  phase3_raw_crossing_summary <- app_joint_qvp_phase4b_read_optional(
    phase3_dir,
    "raw_crossing_summary.csv",
    c("scenario_id", "method", "origin_index", "n_crossing_pairs", "max_crossing_magnitude")
  )
  phase3_monotone_adjustment <- app_joint_qvp_phase4b_read_optional(
    phase3_dir,
    "forecast_monotone_adjustment.csv",
    c("scenario_id", "method", "origin_index", "n_adjusted_quantiles", "max_abs_adjustment", "n_raw_crossing_pairs")
  )

  list(
    phase4_dir = phase4_dir,
    phase3_dir = phase3_dir,
    phase4_manifest = phase4_manifest,
    phase3_manifest = phase3_manifest,
    phase3_recorded_manifest = phase3_recorded_manifest,
    calibration_registry = calibration_registry,
    calibration_run_config = calibration_run_config,
    forecast_metric_distribution_summary = forecast_metric_distribution_summary,
    forecast_metric_by_scenario_summary = forecast_metric_by_scenario_summary,
    forecast_metric_by_family_summary = forecast_metric_by_family_summary,
    forecast_metric_by_tau_summary = forecast_metric_by_tau_summary,
    interval_metric_summary = interval_metric_summary,
    vb_convergence_calibration_summary = vb_convergence_calibration_summary,
    runtime_calibration_summary = runtime_calibration_summary,
    forecast_calibrated_thresholds = forecast_calibrated_thresholds,
    forecast_calibration_assessment = forecast_calibration_assessment,
    article_candidate_run_plan = article_candidate_run_plan,
    phase3_run_config = phase3_run_config,
    phase3_assessment = phase3_assessment,
    phase3_forecast_quantiles = phase3_forecast_quantiles,
    phase3_raw_crossing_summary = phase3_raw_crossing_summary,
    phase3_monotone_adjustment = phase3_monotone_adjustment
  )
}

app_joint_qvp_phase4b_threshold_audit <- function(thresholds) {
  out <- thresholds
  out$finite_pass_threshold <- is.finite(out$recommended_pass_threshold)
  out$finite_review_threshold <- is.na(out$recommended_review_threshold) | is.finite(out$recommended_review_threshold)
  out$has_rationale <- nzchar(as.character(out$rationale))
  out$support_status <- out$status
  out$audit_status <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_phase4b_status(
      hard_fail = !out$finite_pass_threshold[[ii]] || !out$finite_review_threshold[[ii]] || !out$has_rationale[[ii]],
      review = out$status[[ii]] == "needs_more_calibration"
    )
  }, character(1L))
  out$note <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_ts_assessment_note(c(
      if (!out$finite_pass_threshold[[ii]] || !out$finite_review_threshold[[ii]]) "nonfinite threshold",
      if (!out$has_rationale[[ii]]) "missing rationale",
      if (out$status[[ii]] == "needs_more_calibration") "needs more calibration rows",
      if (out$status[[ii]] == "candidate") "candidate threshold support",
      if (out$status[[ii]] == "ready_for_article_candidate") "ready threshold support"
    ))
  }, character(1L))
  out
}

app_joint_qvp_phase4b_scenario_audit <- function(tables) {
  scenario <- merge(
    tables$forecast_metric_by_scenario_summary,
    tables$phase3_assessment[, c("scenario_id", "truth_distance_status", "hit_rate_status", "objective_status", "note"), drop = FALSE],
    by = "scenario_id",
    all.x = TRUE,
    sort = FALSE
  )
  scenario <- merge(
    scenario,
    tables$phase3_run_config[, c("scenario_id", "no_future_test_leakage"), drop = FALSE],
    by = "scenario_id",
    all.x = TRUE,
    sort = FALSE
  )
  if (nrow(tables$phase3_raw_crossing_summary)) {
    raw_counts <- aggregate(n_crossing_pairs ~ scenario_id, tables$phase3_raw_crossing_summary, sum)
    names(raw_counts)[names(raw_counts) == "n_crossing_pairs"] <- "raw_crossing_pairs"
    raw_mag <- aggregate(max_crossing_magnitude ~ scenario_id, tables$phase3_raw_crossing_summary, max)
    names(raw_mag)[names(raw_mag) == "max_crossing_magnitude"] <- "raw_max_crossing_magnitude"
    scenario <- merge(scenario, raw_counts, by = "scenario_id", all.x = TRUE, sort = FALSE)
    scenario <- merge(scenario, raw_mag, by = "scenario_id", all.x = TRUE, sort = FALSE)
  } else {
    scenario$raw_crossing_pairs <- scenario$total_crossing_pairs
    scenario$raw_max_crossing_magnitude <- NA_real_
  }
  if (nrow(tables$phase3_monotone_adjustment)) {
    adjusted <- aggregate(
      cbind(n_adjusted_quantiles, max_abs_adjustment, n_raw_crossing_pairs) ~ scenario_id,
      tables$phase3_monotone_adjustment,
      function(x) if (is.numeric(x)) sum(x, na.rm = TRUE) else NA_real_
    )
    max_adjust <- aggregate(max_abs_adjustment ~ scenario_id, tables$phase3_monotone_adjustment, max)
    adjusted$max_abs_adjustment <- NULL
    adjusted <- merge(adjusted, max_adjust, by = "scenario_id", all.x = TRUE, sort = FALSE)
    names(adjusted)[names(adjusted) == "n_adjusted_quantiles"] <- "monotone_adjusted_quantiles"
    names(adjusted)[names(adjusted) == "max_abs_adjustment"] <- "max_monotone_adjustment"
    names(adjusted)[names(adjusted) == "n_raw_crossing_pairs"] <- "raw_crossing_pairs_from_adjustment"
    scenario <- merge(scenario, adjusted, by = "scenario_id", all.x = TRUE, sort = FALSE)
  } else {
    scenario$monotone_adjusted_quantiles <- NA_real_
    scenario$max_monotone_adjustment <- NA_real_
    scenario$raw_crossing_pairs_from_adjustment <- NA_real_
  }
  scenario$raw_crossing_pairs[is.na(scenario$raw_crossing_pairs)] <- 0
  scenario$monotone_adjusted_quantiles[is.na(scenario$monotone_adjusted_quantiles)] <- 0
  scenario$raw_adjustment_review <- scenario$raw_crossing_pairs > 0 | scenario$monotone_adjusted_quantiles > 0
  metric_cols <- intersect(
    c("truth_normalized_qhat_distance", "rmse_to_truth_mean", "mae_to_truth_mean", "pinball_mean",
      "abs_hit_rate_error_mean", "abs_interval_coverage_error_mean", "wis_mean", "crps_grid_mean"),
    names(scenario)
  )
  scenario$finite_metric_summaries <- if (length(metric_cols)) {
    apply(scenario[, metric_cols, drop = FALSE], 1L, function(x) all(is.finite(as.numeric(x))))
  } else {
    FALSE
  }
  scenario$no_future_test_leakage <- app_as_bool_vec(scenario$no_future_test_leakage)
  scenario$hard_gate_status <- vapply(seq_len(nrow(scenario)), function(ii) {
    app_joint_qvp_phase4b_status(
      hard_fail = !isTRUE(scenario$no_future_test_leakage[[ii]]) ||
        !isTRUE(scenario$finite_metric_summaries[[ii]]) ||
        !is.finite(scenario$total_crossing_pairs[[ii]]) ||
        scenario$total_crossing_pairs[[ii]] > 0 ||
        scenario$gate_status[[ii]] == "fail",
      review = FALSE
    )
  }, character(1L))
  scenario$model_behavior_review <- as.character(scenario$truth_distance_status) == "review" |
    as.character(scenario$hit_rate_status) == "review"
  scenario$compute_control_review <- scenario$vb_max_iter_rate > 0 |
    grepl("VB convergence|max-iteration|max iteration", as.character(scenario$note), ignore.case = TRUE)
  scenario$runtime_review <- FALSE
  if (nrow(scenario) > 2L) {
    med_runtime <- stats::median(scenario$runtime_total_sec, na.rm = TRUE)
    scenario$runtime_review <- is.finite(med_runtime) & med_runtime > 0 &
      scenario$runtime_total_sec > 10 * med_runtime
  }
  scenario$readiness_status <- vapply(seq_len(nrow(scenario)), function(ii) {
    app_joint_qvp_phase4b_status(
      hard_fail = scenario$hard_gate_status[[ii]] == "fail",
      review = scenario$gate_status[[ii]] == "review" ||
        scenario$model_behavior_review[[ii]] ||
        scenario$compute_control_review[[ii]] ||
        scenario$runtime_review[[ii]] ||
        scenario$raw_adjustment_review[[ii]]
    )
  }, character(1L))
  scenario$review_reason <- vapply(seq_len(nrow(scenario)), function(ii) {
    app_joint_qvp_ts_assessment_note(c(
      if (scenario$hard_gate_status[[ii]] == "fail") "hard implementation gate failure",
      if (scenario$model_behavior_review[[ii]]) "truth-distance or hit-rate review",
      if (scenario$compute_control_review[[ii]]) "VB convergence/control review",
      if (scenario$runtime_review[[ii]]) "runtime outlier review",
      if (scenario$raw_adjustment_review[[ii]]) "raw crossing or monotone adjustment review",
      if (nzchar(as.character(scenario$note[[ii]]))) as.character(scenario$note[[ii]])
    ))
  }, character(1L))
  scenario
}

app_joint_qvp_phase4b_family_audit <- function(scenario_audit) {
  families <- unique(scenario_audit$distribution_family)
  rows <- vector("list", length(families))
  for (ii in seq_along(families)) {
    fam <- families[[ii]]
    block <- scenario_audit[scenario_audit$distribution_family == fam, , drop = FALSE]
    rows[[ii]] <- data.frame(
      distribution_family = fam,
      n_registry_rows = nrow(block),
      n_base_scenarios = length(unique(block$base_scenario_id)),
      n_replicates = length(unique(block$replicate_id)),
      hard_pass_count = app_joint_qvp_phase4b_count_status(block$hard_gate_status, "pass"),
      review_count = app_joint_qvp_phase4b_count_status(block$readiness_status, "review"),
      fail_count = app_joint_qvp_phase4b_count_status(block$readiness_status, "fail"),
      mean_truth_normalized_qhat_distance = mean(block$truth_normalized_qhat_distance, na.rm = TRUE),
      max_truth_normalized_qhat_distance = max(block$truth_normalized_qhat_distance, na.rm = TRUE),
      mean_abs_hit_rate_error = mean(block$abs_hit_rate_error_mean, na.rm = TRUE),
      max_vb_max_iter_rate = max(block$vb_max_iter_rate, na.rm = TRUE),
      total_crossing_pairs = sum(block$total_crossing_pairs, na.rm = TRUE),
      readiness_status = app_joint_qvp_phase4b_status(
        hard_fail = any(block$readiness_status == "fail"),
        review = any(block$readiness_status == "review")
      ),
      note = app_joint_qvp_ts_assessment_note(unique(block$review_reason[nzchar(block$review_reason)])),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase4b_tau_audit <- function(forecast_metric_by_tau_summary) {
  out <- forecast_metric_by_tau_summary
  out$instability_ratio_q95_to_median <- abs(out$q95) / pmax(abs(out$median), 1.0e-8)
  out$audit_status <- vapply(seq_len(nrow(out)), function(ii) {
    metric <- as.character(out$metric[[ii]])
    high_calibration_error <- metric %in% c("abs_hit_rate_error") && is.finite(out$q90[[ii]]) && out$q90[[ii]] > 0.25
    app_joint_qvp_phase4b_status(
      hard_fail = !is.finite(out$q90[[ii]]) || !is.finite(out$q95[[ii]]) || out$finite_n[[ii]] <= 0L,
      review = high_calibration_error || (is.finite(out$instability_ratio_q95_to_median[[ii]]) && out$instability_ratio_q95_to_median[[ii]] > 10)
    )
  }, character(1L))
  out$note <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_ts_assessment_note(c(
      if (out$audit_status[[ii]] == "fail") "nonfinite or empty tau metric",
      if (out$metric[[ii]] == "abs_hit_rate_error" && out$q90[[ii]] > 0.25) "large tau hit-rate error",
      if (is.finite(out$instability_ratio_q95_to_median[[ii]]) && out$instability_ratio_q95_to_median[[ii]] > 10) "large q95-to-median instability"
    ))
  }, character(1L))
  out
}

app_joint_qvp_phase4b_vb_runtime_audit <- function(tables, scenario_audit) {
  out <- merge(
    tables$vb_convergence_calibration_summary,
    tables$runtime_calibration_summary[, c("scenario_id", "runtime_total_sec", "runtime_max_sec", "refit_runtime_sec", "forecast_runtime_sec"), drop = FALSE],
    by = "scenario_id",
    all = TRUE,
    sort = FALSE
  )
  out <- merge(
    out,
    scenario_audit[, c("scenario_id", "base_scenario_id", "replicate_id", "distribution_family", "dynamics_class"), drop = FALSE],
    by = "scenario_id",
    all.x = TRUE,
    sort = FALSE
  )
  runtime_median <- stats::median(out$runtime_total_sec, na.rm = TRUE)
  out$runtime_outlier <- is.finite(runtime_median) & runtime_median > 0 & out$runtime_total_sec > 10 * runtime_median
  out$vb_status <- ifelse(is.finite(out$max_iter_rate) & out$max_iter_rate > 0.25, "review", "pass")
  out$runtime_status <- ifelse(out$runtime_outlier, "review", "pass")
  out$readiness_status <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_phase4b_status(
      hard_fail = !is.finite(out$runtime_total_sec[[ii]]) || !is.finite(out$max_iter_rate[[ii]]),
      review = out$vb_status[[ii]] == "review" || out$runtime_status[[ii]] == "review"
    )
  }, character(1L))
  out$note <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_ts_assessment_note(c(
      if (out$vb_status[[ii]] == "review") "VB max-iteration rate above review fraction",
      if (out$runtime_status[[ii]] == "review") "runtime outlier",
      if (out$readiness_status[[ii]] == "fail") "nonfinite runtime or VB rate"
    ))
  }, character(1L))
  out
}

app_joint_qvp_phase4b_readiness_summary <- function(
  tables,
  threshold_audit,
  scenario_audit,
  family_audit,
  tau_audit,
  vb_runtime_audit,
  article_command,
  fallback_calibration_command
) {
  phase4_manifest_ok <- nrow(tables$phase4_manifest) > 0L && all(tables$phase4_manifest$hash_verified)
  phase3_manifest_ok <- nrow(tables$phase3_manifest) > 0L && all(tables$phase3_manifest$hash_verified)
  recorded_phase3_manifest_ok <- nrow(tables$phase3_recorded_manifest) > 0L &&
    all(app_as_bool_vec(tables$phase3_recorded_manifest$file_exists)) &&
    all(app_as_bool_vec(tables$phase3_recorded_manifest$hash_verified))
  leakage_ok <- nrow(tables$phase3_run_config) > 0L &&
    all(app_as_bool_vec(tables$phase3_run_config$no_future_test_leakage))
  finite_forecasts <- nrow(tables$phase3_forecast_quantiles) > 0L &&
    all(is.finite(tables$phase3_forecast_quantiles$qhat)) &&
    all(is.finite(tables$phase3_forecast_quantiles$true_quantile)) &&
    all(is.finite(tables$phase3_forecast_quantiles$pinball_loss))
  total_crossing_pairs <- sum(scenario_audit$total_crossing_pairs, na.rm = TRUE)
  raw_crossing_pairs <- if ("raw_crossing_pairs" %in% names(scenario_audit)) {
    sum(scenario_audit$raw_crossing_pairs, na.rm = TRUE)
  } else {
    total_crossing_pairs
  }
  monotone_adjusted_origins <- if (nrow(tables$phase3_monotone_adjustment)) {
    sum(tables$phase3_monotone_adjustment$n_adjusted_quantiles > 0L, na.rm = TRUE)
  } else {
    0L
  }
  max_monotone_adjustment <- if (nrow(tables$phase3_monotone_adjustment)) {
    max(tables$phase3_monotone_adjustment$max_abs_adjustment, na.rm = TRUE)
  } else {
    NA_real_
  }
  hard_fail <- !phase4_manifest_ok || !phase3_manifest_ok || !recorded_phase3_manifest_ok ||
    !leakage_ok || !finite_forecasts || total_crossing_pairs > 0 ||
    any(threshold_audit$audit_status == "fail") ||
    any(scenario_audit$readiness_status == "fail")
  threshold_review <- any(threshold_audit$audit_status == "review")
  scenario_review <- any(scenario_audit$readiness_status == "review")
  tau_review <- any(tau_audit$audit_status == "review")
  vb_runtime_review <- any(vb_runtime_audit$readiness_status == "review")
  phase4_review <- any(tables$forecast_calibration_assessment$gate_status == "review")
  review <- threshold_review || scenario_review || tau_review || vb_runtime_review || phase4_review
  gate_status <- app_joint_qvp_phase4b_status(hard_fail, review)
  recommendation_status <- if (hard_fail) {
    "blocked_fix_implementation"
  } else if (review) {
    "review_before_article_candidate"
  } else {
    "ready_for_article_candidate"
  }
  recommended_next_command <- if (identical(recommendation_status, "ready_for_article_candidate")) {
    article_command
  } else {
    fallback_calibration_command
  }
  data.frame(
    scope = "phase4b_forecast_calibration_readiness",
    phase4_dir = app_prefer_repo_relative_path(tables$phase4_dir),
    phase3_dir = app_prefer_repo_relative_path(tables$phase3_dir),
    validation_tier = tables$calibration_run_config$validation_tier[[1L]],
    n_registry_rows = nrow(tables$calibration_registry),
    n_base_scenarios = length(unique(tables$calibration_registry$base_scenario_id)),
    n_replicates = tables$calibration_run_config$n_replicates[[1L]],
    phase4_manifest_hashes_verified = phase4_manifest_ok,
    phase3_manifest_hashes_verified = phase3_manifest_ok,
    phase3_recorded_manifest_hashes_verified = recorded_phase3_manifest_ok,
    no_future_test_leakage = leakage_ok,
    finite_forecasts_and_scores = finite_forecasts,
    total_crossing_pairs = total_crossing_pairs,
    raw_crossing_pairs = raw_crossing_pairs,
    monotone_adjusted_origins = monotone_adjusted_origins,
    max_monotone_adjustment = max_monotone_adjustment,
    threshold_rows = nrow(threshold_audit),
    threshold_needs_more_calibration = sum(threshold_audit$status == "needs_more_calibration"),
    threshold_candidate_rows = sum(threshold_audit$status == "candidate"),
    threshold_ready_rows = sum(threshold_audit$status == "ready_for_article_candidate"),
    scenario_pass_rows = app_joint_qvp_phase4b_count_status(scenario_audit$readiness_status, "pass"),
    scenario_review_rows = app_joint_qvp_phase4b_count_status(scenario_audit$readiness_status, "review"),
    scenario_fail_rows = app_joint_qvp_phase4b_count_status(scenario_audit$readiness_status, "fail"),
    family_review_rows = app_joint_qvp_phase4b_count_status(family_audit$readiness_status, "review"),
    tau_review_rows = app_joint_qvp_phase4b_count_status(tau_audit$audit_status, "review"),
    mean_vb_max_iter_rate = mean(vb_runtime_audit$max_iter_rate, na.rm = TRUE),
    max_vb_max_iter_rate = max(vb_runtime_audit$max_iter_rate, na.rm = TRUE),
    runtime_total_sec = sum(vb_runtime_audit$runtime_total_sec, na.rm = TRUE),
    runtime_max_scenario_sec = max(vb_runtime_audit$runtime_total_sec, na.rm = TRUE),
    gate_status = gate_status,
    recommendation_status = recommendation_status,
    recommended_next_command = recommended_next_command,
    note = app_joint_qvp_ts_assessment_note(c(
      if (!phase4_manifest_ok) "Phase 4 artifact hashes missing or unverifiable",
      if (!phase3_manifest_ok || !recorded_phase3_manifest_ok) "Phase 3 artifact hashes missing or unverifiable",
      if (!leakage_ok) "train/test leakage",
      if (!finite_forecasts) "nonfinite forecasts or scores",
      if (total_crossing_pairs > 0) "forecast quantile crossings",
      if (raw_crossing_pairs > 0) "raw forecast crossings reviewed under monotone contract",
      if (monotone_adjusted_origins > 0) "monotone adjustment review",
      if (threshold_review) "thresholds need more calibration support",
      if (scenario_review) "scenario-level reviews remain",
      if (tau_review) "tau-level calibration instability review",
      if (vb_runtime_review) "VB/runtime review remains",
      if (phase4_review) "Phase 4 gate is review"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4b_recommendation <- function(readiness_summary, article_command, fallback_calibration_command) {
  data.frame(
    recommendation_status = readiness_summary$recommendation_status[[1L]],
    gate_status = readiness_summary$gate_status[[1L]],
    article_candidate_ready = readiness_summary$recommendation_status[[1L]] == "ready_for_article_candidate",
    recommended_next_command = readiness_summary$recommended_next_command[[1L]],
    article_candidate_command = article_command,
    fallback_calibration_command = fallback_calibration_command,
    rationale = readiness_summary$note[[1L]],
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4b_readme_lines <- function(readiness_summary, recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Calibration Phase 4b Readiness Audit",
    "",
    "This artifact directory audits a completed Phase 4 calibration run and prepares the next validation decision.",
    "It is not final article evidence; it checks whether the calibration evidence is ready for an article-candidate run.",
    "",
    sprintf("- Phase 4 source: %s", readiness_summary$phase4_dir[[1L]]),
    sprintf("- Validation tier: %s", readiness_summary$validation_tier[[1L]]),
    sprintf("- Registry rows: %s", readiness_summary$n_registry_rows[[1L]]),
    sprintf("- Replicates: %s", readiness_summary$n_replicates[[1L]]),
    sprintf("- Gate: %s", readiness_summary$gate_status[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    "",
    "Primary files:",
    "",
    "- `calibration_readiness_summary.csv`: one-row readiness and manifest summary.",
    "- `threshold_readiness_audit.csv`: threshold support and rationale checks.",
    "- `scenario_failure_mode_audit.csv`: scenario and replicate review reasons.",
    "- `family_failure_mode_audit.csv`: family-level aggregation.",
    "- `tau_failure_mode_audit.csv`: tau-level metric stability checks.",
    "- `vb_runtime_readiness_audit.csv`: VB convergence and runtime readiness.",
    "- `article_candidate_recommendation.csv`: next command and readiness decision.",
    "- `artifact_manifest.csv`: SHA-256 hashes for this audit."
  )
}

app_joint_qvp_audit_synthetic_dgp_forecast_calibration <- function(
  phase4_dir = app_joint_qvp_default_synthetic_dgp_forecast_calibration_dir(),
  out_dir = NULL,
  article_output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_article_candidate_20260702"),
  fallback_calibration_output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_followup_20260702")
) {
  phase4_dir <- normalizePath(phase4_dir, mustWork = TRUE)
  out_dir <- out_dir %||% app_joint_qvp_default_synthetic_dgp_forecast_calibration_readiness_dir(phase4_dir)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  tables <- app_joint_qvp_phase4b_load_artifacts(phase4_dir)
  threshold_readiness_audit <- app_joint_qvp_phase4b_threshold_audit(tables$forecast_calibrated_thresholds)
  scenario_failure_mode_audit <- app_joint_qvp_phase4b_scenario_audit(tables)
  family_failure_mode_audit <- app_joint_qvp_phase4b_family_audit(scenario_failure_mode_audit)
  tau_failure_mode_audit <- app_joint_qvp_phase4b_tau_audit(tables$forecast_metric_by_tau_summary)
  vb_runtime_readiness_audit <- app_joint_qvp_phase4b_vb_runtime_audit(tables, scenario_failure_mode_audit)
  article_command <- app_joint_qvp_phase4b_recommended_article_command(
    tables$article_candidate_run_plan,
    output_dir = article_output_dir
  )
  fallback_command <- app_joint_qvp_phase4b_recommended_calibration_command(
    output_dir = fallback_calibration_output_dir
  )
  calibration_readiness_summary <- app_joint_qvp_phase4b_readiness_summary(
    tables = tables,
    threshold_audit = threshold_readiness_audit,
    scenario_audit = scenario_failure_mode_audit,
    family_audit = family_failure_mode_audit,
    tau_audit = tau_failure_mode_audit,
    vb_runtime_audit = vb_runtime_readiness_audit,
    article_command = article_command,
    fallback_calibration_command = fallback_command
  )
  article_candidate_recommendation <- app_joint_qvp_phase4b_recommendation(
    calibration_readiness_summary,
    article_command,
    fallback_command
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(
    app_joint_qvp_phase4b_readme_lines(calibration_readiness_summary, article_candidate_recommendation),
    readme_path,
    useBytes = TRUE
  )
  paths <- c(
    calibration_readiness_summary = app_joint_qvp_write_csv(calibration_readiness_summary, file.path(out_dir, "calibration_readiness_summary.csv")),
    threshold_readiness_audit = app_joint_qvp_write_csv(threshold_readiness_audit, file.path(out_dir, "threshold_readiness_audit.csv")),
    scenario_failure_mode_audit = app_joint_qvp_write_csv(scenario_failure_mode_audit, file.path(out_dir, "scenario_failure_mode_audit.csv")),
    family_failure_mode_audit = app_joint_qvp_write_csv(family_failure_mode_audit, file.path(out_dir, "family_failure_mode_audit.csv")),
    tau_failure_mode_audit = app_joint_qvp_write_csv(tau_failure_mode_audit, file.path(out_dir, "tau_failure_mode_audit.csv")),
    vb_runtime_readiness_audit = app_joint_qvp_write_csv(vb_runtime_readiness_audit, file.path(out_dir, "vb_runtime_readiness_audit.csv")),
    article_candidate_recommendation = app_joint_qvp_write_csv(article_candidate_recommendation, file.path(out_dir, "article_candidate_recommendation.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    phase4_dir = phase4_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    calibration_readiness_summary = calibration_readiness_summary,
    threshold_readiness_audit = threshold_readiness_audit,
    scenario_failure_mode_audit = scenario_failure_mode_audit,
    family_failure_mode_audit = family_failure_mode_audit,
    tau_failure_mode_audit = tau_failure_mode_audit,
    vb_runtime_readiness_audit = vb_runtime_readiness_audit,
    article_candidate_recommendation = article_candidate_recommendation
  )
}

app_joint_qvp_default_synthetic_dgp_forecast_crossing_audit_dir <- function(artifact_dir) {
  file.path(artifact_dir, "phase4c_crossing_audit")
}

app_joint_qvp_phase4c_resolve_dirs <- function(artifact_dir) {
  artifact_dir <- normalizePath(artifact_dir, mustWork = TRUE)
  phase3_candidate <- file.path(artifact_dir, "phase3_forecast_validation")
  if (dir.exists(phase3_candidate)) {
    return(list(phase4_dir = artifact_dir, phase3_dir = normalizePath(phase3_candidate, mustWork = TRUE)))
  }
  parent <- dirname(artifact_dir)
  phase4_dir <- if (file.exists(file.path(parent, "calibration_registry.csv"))) parent else NA_character_
  list(phase4_dir = phase4_dir, phase3_dir = artifact_dir)
}

app_joint_qvp_phase4c_load_artifacts <- function(artifact_dir) {
  dirs <- app_joint_qvp_phase4c_resolve_dirs(artifact_dir)
  phase3_dir <- dirs$phase3_dir
  phase4_dir <- dirs$phase4_dir
  phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_dir)
  run_config <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "run_config.csv",
    c("scenario_id", "scenario_class", "distribution_family", "dynamics_class", "seed")
  )
  forecast_origin_config <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "forecast_origin_config.csv",
    c("scenario_id", "origin_index", "forecast_time_index", "refit", "fit_origin_index")
  )
  forecast_quantiles <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "forecast_quantiles.csv",
    c("scenario_id", "method", "origin_index", "tau", "qhat", "true_quantile")
  )
  forecast_quantiles_raw <- app_joint_qvp_phase4b_read_optional(
    phase3_dir,
    "forecast_quantiles_raw.csv",
    c("scenario_id", "method", "origin_index", "tau", "qhat", "true_quantile"),
    default = forecast_quantiles
  )
  crossing_summary <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "crossing_summary.csv",
    c("scenario_id", "method", "origin_index", "forecast_time_index", "n_crossing_pairs", "max_crossing_magnitude")
  )
  raw_crossing_summary <- app_joint_qvp_phase4b_read_optional(
    phase3_dir,
    "raw_crossing_summary.csv",
    c("scenario_id", "method", "origin_index", "forecast_time_index", "n_crossing_pairs", "max_crossing_magnitude"),
    default = crossing_summary
  )
  forecast_monotone_adjustment <- app_joint_qvp_phase4b_read_optional(
    phase3_dir,
    "forecast_monotone_adjustment.csv",
    c("scenario_id", "method", "origin_index", "n_adjusted_quantiles", "max_abs_adjustment", "n_raw_crossing_pairs")
  )
  vb_convergence_audit <- app_joint_qvp_phase4b_read_required(
    phase3_dir,
    "vb_convergence_audit.csv",
    c("scenario_id", "origin_index", "refit", "fit_origin_index", "status", "converged", "n_iter")
  )
  calibration_registry <- if (!is.na(phase4_dir) && file.exists(file.path(phase4_dir, "calibration_registry.csv"))) {
    app_read_csv(file.path(phase4_dir, "calibration_registry.csv"))
  } else {
    data.frame()
  }
  list(
    phase4_dir = phase4_dir,
    phase3_dir = phase3_dir,
    phase3_manifest = phase3_manifest,
    run_config = run_config,
    forecast_origin_config = forecast_origin_config,
    forecast_quantiles = forecast_quantiles,
    forecast_quantiles_raw = forecast_quantiles_raw,
    crossing_summary = crossing_summary,
    raw_crossing_summary = raw_crossing_summary,
    forecast_monotone_adjustment = forecast_monotone_adjustment,
    vb_convergence_audit = vb_convergence_audit,
    calibration_registry = calibration_registry
  )
}

app_joint_qvp_phase4c_registry_meta <- function(tables) {
  run_meta <- tables$run_config[, intersect(
    c("scenario_id", "scenario_class", "distribution_family", "dynamics_class", "seed"),
    names(tables$run_config)
  ), drop = FALSE]
  if (nrow(tables$calibration_registry)) {
    reg_cols <- intersect(
      c("scenario_id", "base_scenario_id", "replicate_id", "validation_tier", "seed_role", "base_seed"),
      names(tables$calibration_registry)
    )
    merge(run_meta, tables$calibration_registry[, reg_cols, drop = FALSE], by = "scenario_id", all.x = TRUE, sort = FALSE)
  } else {
    run_meta$base_scenario_id <- run_meta$scenario_id
    run_meta$replicate_id <- NA_integer_
    run_meta$validation_tier <- NA_character_
    run_meta$seed_role <- NA_character_
    run_meta$base_seed <- NA_integer_
    run_meta
  }
}

app_joint_qvp_phase4c_event_audit <- function(tables) {
  events <- tables$raw_crossing_summary[tables$raw_crossing_summary$n_crossing_pairs > 0L, , drop = FALSE]
  if (!nrow(events)) {
    return(data.frame(
      scenario_id = character(), base_scenario_id = character(), replicate_id = integer(),
      origin_index = integer(), forecast_time_index = integer(), method = character(),
      n_raw_crossing_pairs = integer(), raw_max_crossing_magnitude = numeric(),
      n_contract_crossing_pairs = integer(), contract_max_crossing_magnitude = numeric(),
      n_adjusted_quantiles = integer(), max_abs_adjustment = numeric(), refit = logical(),
      fit_origin_index = integer(), distribution_family = character(), dynamics_class = character(),
      stringsAsFactors = FALSE
    ))
  }
  meta <- app_joint_qvp_phase4c_registry_meta(tables)
  contract <- tables$crossing_summary[, c("scenario_id", "origin_index", "n_crossing_pairs", "max_crossing_magnitude"), drop = FALSE]
  names(contract)[names(contract) == "n_crossing_pairs"] <- "n_contract_crossing_pairs"
  names(contract)[names(contract) == "max_crossing_magnitude"] <- "contract_max_crossing_magnitude"
  out <- events
  names(out)[names(out) == "n_crossing_pairs"] <- "n_raw_crossing_pairs"
  names(out)[names(out) == "max_crossing_magnitude"] <- "raw_max_crossing_magnitude"
  out <- merge(out, contract, by = c("scenario_id", "origin_index"), all.x = TRUE, sort = FALSE)
  if (nrow(tables$forecast_monotone_adjustment)) {
    adj_cols <- c("scenario_id", "origin_index", "n_adjusted_quantiles", "max_abs_adjustment", "sum_abs_adjustment", "affected_tau_pairs", "adjustment_status")
    out <- merge(out, tables$forecast_monotone_adjustment[, intersect(adj_cols, names(tables$forecast_monotone_adjustment)), drop = FALSE],
      by = c("scenario_id", "origin_index"), all.x = TRUE, sort = FALSE
    )
  } else {
    out$n_adjusted_quantiles <- NA_integer_
    out$max_abs_adjustment <- NA_real_
    out$sum_abs_adjustment <- NA_real_
    out$affected_tau_pairs <- NA_character_
    out$adjustment_status <- NA_character_
  }
  origin_cols <- intersect(
    c("scenario_id", "origin_index", "forecast_time_index", "forecast_retained_index", "target_y", "refit", "fit_origin_index", "used_fit_n", "used_previous_test_n"),
    names(tables$forecast_origin_config)
  )
  out <- merge(out, tables$forecast_origin_config[, origin_cols, drop = FALSE], by = c("scenario_id", "origin_index", "forecast_time_index"), all.x = TRUE, sort = FALSE)
  out <- merge(out, meta, by = "scenario_id", all.x = TRUE, sort = FALSE)
  out
}

app_joint_qvp_phase4c_pair_detail <- function(tables, events, tolerance = 1.0e-10) {
  if (!nrow(events)) {
    return(data.frame(
      scenario_id = character(), origin_index = integer(), forecast_time_index = integer(),
      lower_tau = numeric(), upper_tau = numeric(), raw_lower_qhat = numeric(),
      raw_upper_qhat = numeric(), contract_lower_qhat = numeric(), contract_upper_qhat = numeric(),
      true_lower_quantile = numeric(), true_upper_quantile = numeric(), crossing_magnitude = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  rows <- list()
  for (ii in seq_len(nrow(events))) {
    id <- events$scenario_id[[ii]]
    origin_index <- events$origin_index[[ii]]
    raw <- tables$forecast_quantiles_raw[tables$forecast_quantiles_raw$scenario_id == id & tables$forecast_quantiles_raw$origin_index == origin_index, , drop = FALSE]
    contract <- tables$forecast_quantiles[tables$forecast_quantiles$scenario_id == id & tables$forecast_quantiles$origin_index == origin_index, , drop = FALSE]
    raw <- raw[order(raw$tau), , drop = FALSE]
    contract <- contract[order(contract$tau), , drop = FALSE]
    diffs <- diff(raw$qhat)
    crossed <- which(diffs < -tolerance)
    if (!length(crossed)) next
    for (jj in crossed) {
      rows[[length(rows) + 1L]] <- data.frame(
        scenario_id = id,
        base_scenario_id = events$base_scenario_id[[ii]],
        replicate_id = events$replicate_id[[ii]],
        origin_index = origin_index,
        forecast_time_index = events$forecast_time_index[[ii]],
        lower_tau = raw$tau[[jj]],
        upper_tau = raw$tau[[jj + 1L]],
        raw_lower_qhat = raw$qhat[[jj]],
        raw_upper_qhat = raw$qhat[[jj + 1L]],
        contract_lower_qhat = contract$qhat[match(raw$tau[[jj]], contract$tau)],
        contract_upper_qhat = contract$qhat[match(raw$tau[[jj + 1L]], contract$tau)],
        true_lower_quantile = raw$true_quantile[[jj]],
        true_upper_quantile = raw$true_quantile[[jj + 1L]],
        crossing_magnitude = raw$qhat[[jj]] - raw$qhat[[jj + 1L]],
        distribution_family = events$distribution_family[[ii]],
        dynamics_class = events$dynamics_class[[ii]],
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

app_joint_qvp_phase4c_vb_context <- function(tables, events) {
  if (!nrow(events)) return(data.frame())
  rows <- vector("list", nrow(events))
  for (ii in seq_len(nrow(events))) {
    id <- events$scenario_id[[ii]]
    origin_index <- events$origin_index[[ii]]
    origin_vb <- tables$vb_convergence_audit[tables$vb_convergence_audit$scenario_id == id & tables$vb_convergence_audit$origin_index == origin_index, , drop = FALSE]
    fit_origin <- if (nrow(origin_vb)) origin_vb$fit_origin_index[[1L]] else events$fit_origin_index[[ii]]
    fit_vb <- tables$vb_convergence_audit[tables$vb_convergence_audit$scenario_id == id & tables$vb_convergence_audit$origin_index == fit_origin, , drop = FALSE]
    if (nrow(fit_vb) > 1L) fit_vb <- fit_vb[app_as_bool_vec(fit_vb$refit), , drop = FALSE]
    rows[[ii]] <- data.frame(
      scenario_id = id,
      base_scenario_id = events$base_scenario_id[[ii]],
      replicate_id = events$replicate_id[[ii]],
      origin_index = origin_index,
      forecast_time_index = events$forecast_time_index[[ii]],
      origin_refit = if (nrow(origin_vb)) app_as_bool_vec(origin_vb$refit)[[1L]] else NA,
      origin_vb_status = if (nrow(origin_vb)) as.character(origin_vb$status[[1L]]) else NA_character_,
      origin_vb_converged = if (nrow(origin_vb)) app_as_bool_vec(origin_vb$converged)[[1L]] else NA,
      fit_origin_index = fit_origin,
      source_fit_status = if (nrow(fit_vb)) as.character(fit_vb$status[[1L]]) else NA_character_,
      source_fit_converged = if (nrow(fit_vb)) app_as_bool_vec(fit_vb$converged)[[1L]] else NA,
      source_fit_n_iter = if (nrow(fit_vb)) fit_vb$n_iter[[1L]] else NA_integer_,
      vb_hit_max_iter = if (nrow(fit_vb)) as.character(fit_vb$status[[1L]]) != "prototype_success" else NA,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase4c_targeted_registry <- function(tables, events) {
  if (!nrow(tables$calibration_registry) || !nrow(events)) return(data.frame())
  ids <- unique(events$scenario_id)
  out <- tables$calibration_registry[tables$calibration_registry$scenario_id %in% ids, , drop = FALSE]
  out[match(ids, out$scenario_id), , drop = FALSE]
}

app_joint_qvp_phase4c_recommendation <- function(events, pair_detail, vb_context, targeted_registry_path, contract_crossing_total) {
  raw_crossing_total <- if (nrow(events)) sum(events$n_raw_crossing_pairs, na.rm = TRUE) else 0L
  max_raw_magnitude <- if (nrow(pair_detail)) max(pair_detail$crossing_magnitude, na.rm = TRUE) else 0
  vb_hit_rate <- if (nrow(vb_context)) mean(app_as_bool_vec(vb_context$vb_hit_max_iter), na.rm = TRUE) else NA_real_
  gate_status <- if (contract_crossing_total > 0L) "fail" else if (raw_crossing_total > 0L || is.finite(vb_hit_rate) && vb_hit_rate > 0) "review" else "pass"
  recommendation_status <- if (contract_crossing_total > 0L) {
    "blocked_contract_crossings"
  } else if (raw_crossing_total > 0L) {
    "contract_unblocked_raw_review"
  } else {
    "ready_no_crossing_events"
  }
  followup_dir <- if (file.exists(targeted_registry_path)) {
    file.path(dirname(dirname(targeted_registry_path)), "phase4c_targeted_crossing_followup")
  } else {
    NA_character_
  }
  command <- if (file.exists(targeted_registry_path)) {
    paste(
      "Rscript application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R",
      sprintf("--registry %s", targeted_registry_path),
      sprintf("--output-dir %s", followup_dir),
      "--vb-max-iter 240",
      "--adaptive-vb-max-iter-grid 240,360",
      "--refit-stride 20",
      "--forecast-origin-stride 10",
      "--max-origins-per-scenario 40"
    )
  } else {
    NA_character_
  }
  data.frame(
    gate_status = gate_status,
    recommendation_status = recommendation_status,
    raw_crossing_pairs = raw_crossing_total,
    contract_crossing_pairs = contract_crossing_total,
    crossing_event_rows = nrow(events),
    crossing_pair_rows = nrow(pair_detail),
    max_raw_crossing_magnitude = max_raw_magnitude,
    vb_source_fit_max_iter_rate = vb_hit_rate,
    targeted_registry_path = if (file.exists(targeted_registry_path)) app_prefer_repo_relative_path(targeted_registry_path) else NA_character_,
    recommended_followup_command = command,
    rationale = app_joint_qvp_ts_assessment_note(c(
      if (contract_crossing_total > 0L) "contract forecast quantiles still cross",
      if (raw_crossing_total > 0L) "raw forecast crossings require monotone contract review",
      if (is.finite(vb_hit_rate) && vb_hit_rate > 0) "crossing origins tied to max-iteration VB source fits"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4c_readme_lines <- function(recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Crossing Audit Phase 4c",
    "",
    "This artifact directory audits raw forecast quantile crossings and preserves the exact crossing-registry rows for follow-up runs.",
    "Raw model crossings are diagnostic evidence. Contract forecast quantiles are the monotone outputs used for scoring after the Phase 4c contract.",
    "",
    sprintf("- Gate: %s", recommendation$gate_status[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    sprintf("- Raw crossing pairs: %s", recommendation$raw_crossing_pairs[[1L]]),
    sprintf("- Contract crossing pairs: %s", recommendation$contract_crossing_pairs[[1L]]),
    "",
    "Primary files:",
    "",
    "- `crossing_event_audit.csv`: crossing origins and scenario metadata.",
    "- `crossing_origin_context.csv`: rolling-origin context for crossing origins.",
    "- `crossing_pair_detail.csv`: adjacent tau-pair crossing details.",
    "- `crossing_vb_context.csv`: source-fit VB convergence context.",
    "- `targeted_crossing_registry.csv`: exact registry rows for crossing follow-up when available.",
    "- `crossing_remediation_recommendation.csv`: conservative next action.",
    "- `artifact_manifest.csv`: SHA-256 hashes for this audit."
  )
}

app_joint_qvp_audit_synthetic_dgp_forecast_crossings <- function(
  artifact_dir,
  out_dir = NULL
) {
  dirs <- app_joint_qvp_phase4c_resolve_dirs(artifact_dir)
  out_dir <- out_dir %||% app_joint_qvp_default_synthetic_dgp_forecast_crossing_audit_dir(artifact_dir)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  tables <- app_joint_qvp_phase4c_load_artifacts(artifact_dir)
  crossing_event_audit <- app_joint_qvp_phase4c_event_audit(tables)
  crossing_pair_detail <- app_joint_qvp_phase4c_pair_detail(tables, crossing_event_audit)
  crossing_origin_context <- crossing_event_audit[, intersect(
    c("scenario_id", "base_scenario_id", "replicate_id", "origin_index", "forecast_time_index", "forecast_retained_index",
      "target_y", "refit", "fit_origin_index", "used_fit_n", "used_previous_test_n", "distribution_family", "dynamics_class"),
    names(crossing_event_audit)
  ), drop = FALSE]
  crossing_vb_context <- app_joint_qvp_phase4c_vb_context(tables, crossing_event_audit)
  targeted_crossing_registry <- app_joint_qvp_phase4c_targeted_registry(tables, crossing_event_audit)
  targeted_registry_path <- file.path(out_dir, "targeted_crossing_registry.csv")
  if (nrow(targeted_crossing_registry)) app_joint_qvp_write_csv(targeted_crossing_registry, targeted_registry_path)
  contract_crossing_total <- sum(tables$crossing_summary$n_crossing_pairs, na.rm = TRUE)
  crossing_remediation_recommendation <- app_joint_qvp_phase4c_recommendation(
    crossing_event_audit,
    crossing_pair_detail,
    crossing_vb_context,
    targeted_registry_path,
    contract_crossing_total
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase4c_readme_lines(crossing_remediation_recommendation), readme_path, useBytes = TRUE)
  paths <- c(
    crossing_event_audit = app_joint_qvp_write_csv(crossing_event_audit, file.path(out_dir, "crossing_event_audit.csv")),
    crossing_origin_context = app_joint_qvp_write_csv(crossing_origin_context, file.path(out_dir, "crossing_origin_context.csv")),
    crossing_pair_detail = app_joint_qvp_write_csv(crossing_pair_detail, file.path(out_dir, "crossing_pair_detail.csv")),
    crossing_vb_context = app_joint_qvp_write_csv(crossing_vb_context, file.path(out_dir, "crossing_vb_context.csv")),
    crossing_remediation_recommendation = app_joint_qvp_write_csv(crossing_remediation_recommendation, file.path(out_dir, "crossing_remediation_recommendation.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  if (nrow(targeted_crossing_registry)) {
    paths <- c(paths, targeted_crossing_registry = normalizePath(targeted_registry_path, mustWork = TRUE))
  }
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    phase3_dir = dirs$phase3_dir,
    phase4_dir = dirs$phase4_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    crossing_event_audit = crossing_event_audit,
    crossing_pair_detail = crossing_pair_detail,
    crossing_vb_context = crossing_vb_context,
    targeted_crossing_registry = targeted_crossing_registry,
    crossing_remediation_recommendation = crossing_remediation_recommendation
  )
}

app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702")
}

app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_preflight_dir <- function(out_dir) {
  file.path(out_dir, "phase4d_contract_calibration_preflight")
}

app_joint_qvp_phase4d_contract_commands <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir(),
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  scenario_ids = NULL,
  tier = "calibration",
  n_replicates = 5L,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL,
  vb_max_iter = 240L,
  adaptive_vb_max_iter_grid = c(240L, 360L),
  refit_stride = 20L,
  forecast_origin_stride = 10L,
  max_origins_per_scenario = 40L,
  article_output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_article_candidate_20260702"),
  fallback_calibration_output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_followup_20260702")
) {
  arg <- function(flag, value) {
    if (is.null(value) || length(value) == 0L || is.na(value[[1L]]) || !nzchar(as.character(value[[1L]]))) return(character())
    c(flag, as.character(value[[1L]]))
  }
  len_args <- c(
    arg("--seed-base", seed_base),
    arg("--simulated-length", simulated_length),
    arg("--washout-length", washout_length),
    arg("--train-length", train_length),
    arg("--test-length", test_length)
  )
  scenario_arg <- if (!is.null(scenario_ids) && length(scenario_ids)) {
    c("--scenario-ids", paste(scenario_ids, collapse = ","))
  } else {
    character()
  }
  phase4 <- paste(c(
    "Rscript", "application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R",
    "--registry", registry_path,
    "--tier", tier,
    "--output-dir", out_dir,
    scenario_arg,
    "--n-replicates", as.character(n_replicates),
    len_args,
    "--vb-max-iter", as.character(vb_max_iter),
    "--adaptive-vb-max-iter-grid", paste(as.integer(adaptive_vb_max_iter_grid), collapse = ","),
    "--refit-stride", as.character(refit_stride),
    "--forecast-origin-stride", as.character(forecast_origin_stride),
    "--max-origins-per-scenario", as.character(max_origins_per_scenario)
  ), collapse = " ")
  phase4b <- paste(c(
    "Rscript", "application/scripts/79_audit_joint_qvp_synthetic_dgp_forecast_calibration.R",
    "--phase4-dir", out_dir,
    "--output-dir", file.path(out_dir, "phase4b_readiness_audit"),
    "--article-output-dir", article_output_dir,
    "--fallback-calibration-output-dir", fallback_calibration_output_dir
  ), collapse = " ")
  phase4c <- paste(c(
    "Rscript", "application/scripts/80_audit_joint_qvp_synthetic_dgp_forecast_crossings.R",
    "--artifact-dir", out_dir,
    "--output-dir", file.path(out_dir, "phase4c_crossing_audit")
  ), collapse = " ")
  data.frame(
    step_order = c(1L, 2L, 3L),
    step_id = c("phase4_contract_calibration", "phase4b_readiness_audit", "phase4c_crossing_audit"),
    command = c(phase4, phase4b, phase4c),
    rationale = c(
      "Run full calibration-size campaign under the raw/contract monotone forecast policy.",
      "Audit manifests, leakage, finiteness, thresholds, raw adjustments, VB convergence, and readiness.",
      "Audit raw crossing events and verify contract forecast crossings remain zero."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4d_expected_artifacts <- function(out_dir) {
  rows <- list(
    data.frame(scope = "phase4", relative_path = c(
      "calibration_registry.csv",
      "calibration_run_config.csv",
      "forecast_calibrated_thresholds.csv",
      "forecast_calibration_assessment.csv",
      "phase3_artifact_manifest.csv",
      "artifact_manifest.csv"
    ), required_for_readiness = TRUE, stringsAsFactors = FALSE),
    data.frame(scope = "phase3_nested", relative_path = file.path("phase3_forecast_validation", c(
      "forecast_quantiles_raw.csv",
      "forecast_quantiles.csv",
      "forecast_monotone_adjustment.csv",
      "raw_crossing_summary.csv",
      "crossing_summary.csv",
      "forecast_validation_assessment.csv",
      "artifact_manifest.csv"
    )), required_for_readiness = TRUE, stringsAsFactors = FALSE),
    data.frame(scope = "phase4b_audit", relative_path = file.path("phase4b_readiness_audit", c(
      "calibration_readiness_summary.csv",
      "scenario_failure_mode_audit.csv",
      "article_candidate_recommendation.csv",
      "artifact_manifest.csv"
    )), required_for_readiness = TRUE, stringsAsFactors = FALSE),
    data.frame(scope = "phase4c_audit", relative_path = file.path("phase4c_crossing_audit", c(
      "crossing_event_audit.csv",
      "crossing_pair_detail.csv",
      "crossing_remediation_recommendation.csv",
      "artifact_manifest.csv"
    )), required_for_readiness = TRUE, stringsAsFactors = FALSE)
  )
  out <- app_bind_rows_fill(rows)
  out$artifact_root <- app_prefer_repo_relative_path(out_dir)
  out
}

app_joint_qvp_phase4d_preflight_rows <- function(
  registry_path,
  out_dir,
  calibration_registry,
  commands,
  expected_artifacts
) {
  scripts <- c(
    "application/scripts/78_run_joint_qvp_synthetic_dgp_forecast_calibration.R",
    "application/scripts/79_audit_joint_qvp_synthetic_dgp_forecast_calibration.R",
    "application/scripts/80_audit_joint_qvp_synthetic_dgp_forecast_crossings.R"
  )
  docs <- c(
    "docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_calibration_phase4_20260702.md",
    "docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_calibration_phase4b_readiness_20260702.md",
    "docs/implementation_notes/joint_qvp_synthetic_dgp_forecast_crossing_phase4c_20260702.md"
  )
  checks <- list(
    data.frame(check_name = "registry_exists", status = if (file.exists(registry_path)) "pass" else "fail", detail = registry_path, stringsAsFactors = FALSE),
    data.frame(check_name = "scripts_exist", status = if (all(file.exists(app_path(scripts)))) "pass" else "fail", detail = paste(scripts, collapse = ";"), stringsAsFactors = FALSE),
    data.frame(check_name = "docs_exist", status = if (all(file.exists(app_path(docs)))) "pass" else "fail", detail = paste(docs, collapse = ";"), stringsAsFactors = FALSE),
    data.frame(check_name = "phase3_contract_function", status = if (exists("app_joint_qvp_phase3_contract_forecast", mode = "function")) "pass" else "fail", detail = "app_joint_qvp_phase3_contract_forecast", stringsAsFactors = FALSE),
    data.frame(check_name = "crossing_audit_function", status = if (exists("app_joint_qvp_audit_synthetic_dgp_forecast_crossings", mode = "function")) "pass" else "fail", detail = "app_joint_qvp_audit_synthetic_dgp_forecast_crossings", stringsAsFactors = FALSE),
    data.frame(check_name = "calibration_registry_schema", status = tryCatch({ app_joint_qvp_validate_synthetic_dgp_registry(calibration_registry); "pass" }, error = function(e) "fail"), detail = sprintf("%s rows", nrow(calibration_registry)), stringsAsFactors = FALSE),
    data.frame(check_name = "unique_replicated_scenario_ids", status = if (!anyDuplicated(calibration_registry$scenario_id)) "pass" else "fail", detail = sprintf("%s unique ids", length(unique(calibration_registry$scenario_id))), stringsAsFactors = FALSE),
    data.frame(check_name = "seed_reproducibility_fields", status = if (all(c("seed", "seed_role", "replicate_id", "base_scenario_id") %in% names(calibration_registry))) "pass" else "fail", detail = paste(intersect(c("seed", "seed_role", "replicate_id", "base_scenario_id"), names(calibration_registry)), collapse = ","), stringsAsFactors = FALSE),
    data.frame(check_name = "raw_contract_expected_artifacts", status = if (all(c("phase3_nested", "phase4b_audit", "phase4c_audit") %in% expected_artifacts$scope)) "pass" else "fail", detail = sprintf("%s expected files", nrow(expected_artifacts)), stringsAsFactors = FALSE),
    data.frame(check_name = "commands_recorded", status = if (nrow(commands) == 3L && all(nzchar(commands$command))) "pass" else "fail", detail = paste(commands$step_id, collapse = ","), stringsAsFactors = FALSE),
    data.frame(check_name = "output_directory_declared", status = if (nzchar(out_dir)) "pass" else "fail", detail = out_dir, stringsAsFactors = FALSE)
  )
  out <- do.call(rbind, checks)
  out$gate_status <- ifelse(out$status == "pass", "pass", "fail")
  out
}

app_joint_qvp_phase4d_readme_lines <- function(plan, preflight) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Calibration Contract Rerun",
    "",
    "This directory prepares the full calibration-size rerun under the Phase 4c raw/contract forecast policy.",
    "It is a launch and audit runbook: the heavy calibration run is separate from this preflight unless the wrapper is called with `--execute true`.",
    "",
    sprintf("- Output directory: %s", plan$output_dir[[1L]]),
    sprintf("- Tier: %s", plan$tier[[1L]]),
    sprintf("- Base scenarios: %s", plan$n_base_scenarios[[1L]]),
    sprintf("- Replicates per base scenario: %s", plan$n_replicates[[1L]]),
    sprintf("- Replicated registry rows: %s", plan$n_registry_rows[[1L]]),
    sprintf("- Forecast origins per replicated scenario: %s", plan$max_origins_per_scenario[[1L]]),
    sprintf("- VB controls: max_iter=%s; adaptive_grid=%s", plan$vb_max_iter[[1L]], plan$adaptive_vb_max_iter_grid[[1L]]),
    sprintf("- Preflight gate: %s", if (all(preflight$status == "pass")) "pass" else "fail"),
    "",
    "Primary preflight files:",
    "",
    "- `contract_rerun_plan.csv`: selected controls, expected size, and source paths.",
    "- `contract_rerun_commands.csv`: exact Phase 4, Phase 4b, and Phase 4c commands.",
    "- `contract_rerun_preflight.csv`: launch checks.",
    "- `expected_artifacts.csv`: files that should exist after the full run and audits.",
    "- `calibration_registry_preview.csv`: exact replicated registry rows that will be used.",
    "- `artifact_manifest.csv`: SHA-256 hashes for the preflight artifact."
  )
}

app_joint_qvp_prepare_synthetic_dgp_forecast_contract_calibration_rerun <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir(),
  prep_dir = NULL,
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  scenario_ids = NULL,
  tier = "calibration",
  n_replicates = 5L,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL,
  vb_max_iter = 240L,
  adaptive_vb_max_iter_grid = c(240L, 360L),
  refit_stride = 20L,
  forecast_origin_stride = 10L,
  max_origins_per_scenario = 40L,
  article_output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_article_candidate_20260702"),
  fallback_calibration_output_dir = app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_followup_20260702")
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  prep_dir <- prep_dir %||% app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_preflight_dir(out_dir)
  prep_dir <- normalizePath(prep_dir, mustWork = FALSE)
  dir.create(prep_dir, recursive = TRUE, showWarnings = FALSE)
  defaults <- app_joint_qvp_phase4_tier_defaults(tier)
  n_replicates <- as.integer(n_replicates %||% defaults$n_replicates)
  seed_base <- seed_base %||% defaults$seed_base
  simulated_length <- simulated_length %||% defaults$simulated_length
  washout_length <- washout_length %||% defaults$washout_length
  train_length <- train_length %||% defaults$train_length
  test_length <- test_length %||% defaults$test_length
  calibration_registry <- app_joint_qvp_phase4_build_calibration_registry(
    registry_path = registry_path,
    scenario_ids = scenario_ids,
    tier = tier,
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length
  )
  commands <- app_joint_qvp_phase4d_contract_commands(
    out_dir = out_dir,
    registry_path = registry_path,
    scenario_ids = scenario_ids,
    tier = tier,
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = max_origins_per_scenario,
    article_output_dir = article_output_dir,
    fallback_calibration_output_dir = fallback_calibration_output_dir
  )
  expected_artifacts <- app_joint_qvp_phase4d_expected_artifacts(out_dir)
  preflight <- app_joint_qvp_phase4d_preflight_rows(
    registry_path = registry_path,
    out_dir = out_dir,
    calibration_registry = calibration_registry,
    commands = commands,
    expected_artifacts = expected_artifacts
  )
  plan <- data.frame(
    output_dir = app_prefer_repo_relative_path(out_dir),
    preflight_dir = app_prefer_repo_relative_path(prep_dir),
    registry_path = app_prefer_repo_relative_path(registry_path),
    tier = tier,
    n_base_scenarios = length(unique(calibration_registry$base_scenario_id)),
    n_replicates = n_replicates,
    n_registry_rows = nrow(calibration_registry),
    seed_base = as.integer(seed_base),
    simulated_length = as.integer(simulated_length),
    washout_length = as.integer(washout_length),
    train_length = as.integer(train_length),
    test_length = as.integer(test_length),
    vb_max_iter = as.integer(vb_max_iter),
    adaptive_vb_max_iter_grid = paste(as.integer(adaptive_vb_max_iter_grid), collapse = ","),
    refit_stride = as.integer(refit_stride),
    forecast_origin_stride = as.integer(forecast_origin_stride),
    max_origins_per_scenario = as.integer(max_origins_per_scenario),
    expected_forecast_origin_rows = nrow(calibration_registry) * as.integer(max_origins_per_scenario),
    expected_forecast_quantile_rows = nrow(calibration_registry) * as.integer(max_origins_per_scenario) * length(app_joint_qvp_parse_tau_spec(calibration_registry$tau_grid[[1L]])),
    phase4b_audit_dir = app_prefer_repo_relative_path(file.path(out_dir, "phase4b_readiness_audit")),
    phase4c_audit_dir = app_prefer_repo_relative_path(file.path(out_dir, "phase4c_crossing_audit")),
    preflight_gate = if (all(preflight$status == "pass")) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(prep_dir, "README.md")
  writeLines(app_joint_qvp_phase4d_readme_lines(plan, preflight), readme_path, useBytes = TRUE)
  paths <- c(
    contract_rerun_plan = app_joint_qvp_write_csv(plan, file.path(prep_dir, "contract_rerun_plan.csv")),
    contract_rerun_commands = app_joint_qvp_write_csv(commands, file.path(prep_dir, "contract_rerun_commands.csv")),
    contract_rerun_preflight = app_joint_qvp_write_csv(preflight, file.path(prep_dir, "contract_rerun_preflight.csv")),
    expected_artifacts = app_joint_qvp_write_csv(expected_artifacts, file.path(prep_dir, "expected_artifacts.csv")),
    calibration_registry_preview = app_joint_qvp_write_csv(calibration_registry, file.path(prep_dir, "calibration_registry_preview.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(prep_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(prep_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    prep_dir = prep_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    plan = plan,
    commands = commands,
    preflight = preflight,
    expected_artifacts = expected_artifacts,
    calibration_registry = calibration_registry
  )
}

app_joint_qvp_default_synthetic_dgp_phase4g_targeted_registry_path <- function() {
  file.path(
    app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir(),
    "phase4c_crossing_audit",
    "targeted_crossing_registry.csv"
  )
}

app_joint_qvp_default_synthetic_dgp_phase4g_screen_dir <- function() {
  file.path(
    app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir(),
    "phase4g_prior_design_screen"
  )
}

app_joint_qvp_default_synthetic_dgp_phase4h_screen_dir <- function() {
  file.path(
    app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir(),
    "phase4h_tau0_refinement"
  )
}

app_joint_qvp_default_synthetic_dgp_phase4i_candidate_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4i_tau0_candidate_pilot_20260704")
}

app_joint_qvp_phase4_screen_id_number_label <- function(x) {
  x <- as.numeric(x)
  if (length(x) != 1L || !is.finite(x) || x <= 0) {
    stop("Screen-grid numeric labels require one positive finite value.", call. = FALSE)
  }
  label <- format(x, scientific = FALSE, trim = TRUE, digits = 10)
  label <- sub("0+$", "", label)
  label <- sub("\\.$", "", label)
  gsub("\\.", "p", label)
}

app_joint_qvp_validate_phase4_screen_grid <- function(grid, label = "Phase 4 screen grid") {
  required <- c(
    "screen_id", "screen_class", "tau0", "zeta2", "alpha_prior_sd",
    "rhs_vb_inner", "alpha_min_spacing", "rationale"
  )
  app_check_required_columns(grid, required, label)
  if (!nrow(grid)) stop(sprintf("%s is empty.", label), call. = FALSE)
  grid$screen_id <- as.character(grid$screen_id)
  grid$screen_class <- as.character(grid$screen_class)
  grid$rationale <- as.character(grid$rationale)
  grid$tau0 <- as.numeric(grid$tau0)
  grid$zeta2 <- as.numeric(grid$zeta2)
  grid$alpha_prior_sd <- as.numeric(grid$alpha_prior_sd)
  grid$rhs_vb_inner <- as.integer(grid$rhs_vb_inner)
  grid$alpha_min_spacing <- as.numeric(grid$alpha_min_spacing)
  if (any(!nzchar(grid$screen_id))) stop(sprintf("%s contains empty screen ids.", label), call. = FALSE)
  if (anyDuplicated(grid$screen_id)) stop(sprintf("%s screen ids must be unique.", label), call. = FALSE)
  if (any(!is.finite(grid$tau0) | grid$tau0 <= 0)) stop(sprintf("%s tau0 values must be positive and finite.", label), call. = FALSE)
  if (any((!is.finite(grid$zeta2) & !is.infinite(grid$zeta2)) | grid$zeta2 <= 0)) {
    stop(sprintf("%s zeta2 values must be positive finite values or Inf.", label), call. = FALSE)
  }
  if (any((!is.finite(grid$alpha_prior_sd) & !is.infinite(grid$alpha_prior_sd)) | grid$alpha_prior_sd <= 0)) {
    stop(sprintf("%s alpha_prior_sd values must be positive finite values or Inf.", label), call. = FALSE)
  }
  if (any(!is.finite(grid$rhs_vb_inner) | grid$rhs_vb_inner <= 0L)) {
    stop(sprintf("%s rhs_vb_inner values must be positive integers.", label), call. = FALSE)
  }
  if (any(!is.finite(grid$alpha_min_spacing) | grid$alpha_min_spacing < 0)) {
    stop(sprintf("%s alpha_min_spacing values must be nonnegative and finite.", label), call. = FALSE)
  }
  rownames(grid) <- NULL
  grid
}

app_joint_qvp_phase4g_screen_grid <- function(
  tier = c("smoke", "targeted"),
  screen_ids = NULL
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "targeted"))
  grid <- data.frame(
    screen_id = c(
      "baseline_vb480",
      "tau0_0p5",
      "tau0_0p25",
      "tau0_0p1",
      "zeta2_10",
      "zeta2_4",
      "tau0_0p5_zeta2_10",
      "tau0_0p25_zeta2_10",
      "alpha_sd_0p5",
      "rhs_inner_8"
    ),
    screen_class = c(
      "baseline",
      rep("rhs_global_shrinkage", 3L),
      rep("rhs_coefficient_coupling", 2L),
      rep("combined_shrinkage_coupling", 2L),
      "intercept_shrinkage",
      "rhs_vb_depth"
    ),
    tau0 = c(1, 0.5, 0.25, 0.10, 1, 1, 0.5, 0.25, 1, 1),
    zeta2 = c(Inf, Inf, Inf, Inf, 10, 4, 10, 10, Inf, Inf),
    alpha_prior_sd = c(1, 1, 1, 1, 1, 1, 1, 1, 0.5, 1),
    rhs_vb_inner = c(5L, 5L, 5L, 5L, 5L, 5L, 5L, 5L, 5L, 8L),
    alpha_min_spacing = rep(0, 10L),
    rationale = c(
      "Reference Phase 4e stronger-VB control with existing weak global RHS shrinkage.",
      "Moderate stronger global RHS shrinkage because tau2 = tau0^2 enters the RHS innovation precision.",
      "Strong global RHS shrinkage to test whether smoother coefficients reduce raw tail crossings.",
      "Very strong global RHS shrinkage used as an intentionally aggressive diagnostic.",
      "Shared-coefficient coupling through finite zeta2 while preserving baseline tau0.",
      "Stronger shared-coefficient coupling through smaller zeta2 while preserving baseline tau0.",
      "Combined moderate global shrinkage and shared-coefficient coupling.",
      "Combined strong global shrinkage and shared-coefficient coupling.",
      "Tighter alpha prior to reduce intercept noise while leaving RHS shrinkage unchanged.",
      "More RHS inner VB updates to test whether prior-state stabilization reduces raw crossings."
    ),
    stringsAsFactors = FALSE
  )
  if (identical(tier, "smoke") && (is.null(screen_ids) || !length(screen_ids))) {
    keep <- c("baseline_vb480", "tau0_0p5", "zeta2_10")
    grid <- grid[match(keep, grid$screen_id), , drop = FALSE]
  }
  if (!is.null(screen_ids) && length(screen_ids)) {
    screen_ids <- unique(as.character(screen_ids))
    screen_ids <- screen_ids[nzchar(screen_ids)]
    missing_ids <- setdiff(screen_ids, grid$screen_id)
    if (length(missing_ids)) {
      stop("Requested Phase 4g screen id(s) not found: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    grid <- grid[match(screen_ids, grid$screen_id), , drop = FALSE]
  }
  rownames(grid) <- NULL
  app_joint_qvp_validate_phase4_screen_grid(grid, "Phase 4g screen grid")
}

app_joint_qvp_phase4h_tau0_screen_grid <- function(
  tau0_grid = c(0.25, 0.20, 0.15, 0.10, 0.075, 0.05),
  include_secondary_grid = FALSE,
  screen_ids = NULL
) {
  tau0_grid <- as.numeric(tau0_grid)
  tau0_grid <- tau0_grid[is.finite(tau0_grid) & tau0_grid > 0]
  if (!length(tau0_grid)) stop("Phase 4h tau0 grid must contain positive finite values.", call. = FALSE)
  tau0_grid <- unique(tau0_grid)
  labels <- vapply(tau0_grid, app_joint_qvp_phase4_screen_id_number_label, character(1L))
  primary <- data.frame(
    screen_id = paste0("tau0_", labels),
    screen_class = "tau0_local_refinement",
    tau0 = tau0_grid,
    zeta2 = Inf,
    alpha_prior_sd = 1,
    rhs_vb_inner = 5L,
    alpha_min_spacing = 0,
    rationale = sprintf("Phase 4h local tau0 refinement candidate tau0 = %s.", tau0_grid),
    stringsAsFactors = FALSE
  )
  primary$screen_id[abs(primary$tau0 - 0.25) < 1.0e-12] <- "tau0_0p25_reference"
  primary$screen_id[abs(primary$tau0 - 0.10) < 1.0e-12] <- "tau0_0p10_reference"
  primary$rationale[primary$screen_id == "tau0_0p25_reference"] <- "Stable Phase 4g tau0 reference with lower VB max-iteration pressure than tau0 0.10."
  primary$rationale[primary$screen_id == "tau0_0p10_reference"] <- "Current Phase 4g best raw-crossing and truth-MAE reference."
  grid <- primary
  if (isTRUE(include_secondary_grid)) {
    secondary <- data.frame(
      screen_id = c("tau0_0p10_alpha_sd_0p5", "tau0_0p15_alpha_sd_0p5", "tau0_0p10_zeta2_10"),
      screen_class = c("tau0_alpha_secondary", "tau0_alpha_secondary", "tau0_zeta_secondary"),
      tau0 = c(0.10, 0.15, 0.10),
      zeta2 = c(Inf, Inf, 10),
      alpha_prior_sd = c(0.5, 0.5, 1),
      rhs_vb_inner = c(5L, 5L, 5L),
      alpha_min_spacing = c(0, 0, 0),
      rationale = c(
        "Secondary check whether intercept shrinkage stabilizes tau0 0.10.",
        "Secondary check whether intercept shrinkage stabilizes a compromise tau0 0.15.",
        "Secondary check whether finite zeta2 coupling helps the upper tail at tau0 0.10."
      ),
      stringsAsFactors = FALSE
    )
    grid <- rbind(grid, secondary)
  }
  grid <- app_joint_qvp_validate_phase4_screen_grid(grid, "Phase 4h tau0 refinement grid")
  if (!is.null(screen_ids) && length(screen_ids)) {
    screen_ids <- unique(as.character(screen_ids))
    screen_ids <- screen_ids[nzchar(screen_ids)]
    missing_ids <- setdiff(screen_ids, grid$screen_id)
    if (length(missing_ids)) {
      stop("Requested Phase 4h screen id(s) not found: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    grid <- grid[match(screen_ids, grid$screen_id), , drop = FALSE]
  }
  rownames(grid) <- NULL
  grid
}

app_joint_qvp_phase4g_load_targeted_registry <- function(
  targeted_registry_path = app_joint_qvp_default_synthetic_dgp_phase4g_targeted_registry_path(),
  targeted_registry = NULL,
  scenario_ids = NULL,
  tier = c("smoke", "targeted")
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "targeted"))
  registry <- if (is.null(targeted_registry)) {
    targeted_registry_path <- normalizePath(targeted_registry_path, mustWork = TRUE)
    app_read_csv(targeted_registry_path)
  } else {
    targeted_registry
  }
  app_joint_qvp_validate_synthetic_dgp_registry(registry)
  if ("enabled" %in% names(registry)) registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
  available <- unique(as.character(registry$scenario_id))
  if ("base_scenario_id" %in% names(registry)) available <- unique(c(available, as.character(registry$base_scenario_id)))
  if (!is.null(scenario_ids) && length(scenario_ids)) {
    scenario_ids <- unique(as.character(scenario_ids))
    scenario_ids <- scenario_ids[nzchar(scenario_ids)]
    matched <- registry$scenario_id %in% scenario_ids
    if ("base_scenario_id" %in% names(registry)) {
      matched <- matched | registry$base_scenario_id %in% scenario_ids
    }
    missing_ids <- setdiff(scenario_ids, available)
    if (length(missing_ids)) {
      stop("Requested Phase 4g scenario id(s) not found in targeted registry: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    registry <- registry[matched, , drop = FALSE]
  } else if (identical(tier, "smoke") && nrow(registry) > 2L) {
    registry <- registry[seq_len(2L), , drop = FALSE]
  }
  if (!nrow(registry)) stop("No Phase 4g targeted registry rows selected.", call. = FALSE)
  if (anyDuplicated(registry$scenario_id)) stop("Phase 4g targeted registry scenario ids must be unique.", call. = FALSE)
  rownames(registry) <- NULL
  registry
}

app_joint_qvp_phase4g_read_phase3 <- function(phase3_dir, filename, required_cols = character()) {
  out <- app_read_csv(file.path(phase3_dir, filename))
  if (length(required_cols)) app_check_required_columns(out, required_cols, filename)
  out
}

app_joint_qvp_phase4g_screen_metrics <- function(phase3_dir, screen_row) {
  run_config <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "run_config.csv",
    c("scenario_id", "n_forecast_origins", "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner")
  )
  raw_crossing <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "raw_crossing_summary.csv",
    c("scenario_id", "origin_index", "n_crossing_pairs", "max_crossing_magnitude")
  )
  contract_crossing <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "crossing_summary.csv",
    c("scenario_id", "origin_index", "n_crossing_pairs", "max_crossing_magnitude")
  )
  adjustment <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "forecast_monotone_adjustment.csv",
    c("scenario_id", "origin_index", "n_adjusted_quantiles", "max_abs_adjustment", "n_raw_crossing_pairs")
  )
  truth <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "forecast_truth_comparison.csv",
    c("scenario_id", "method", "tau", "rmse_to_truth", "mae_to_truth")
  )
  hit <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "hit_rate_summary.csv",
    c("scenario_id", "method", "tau", "hit_rate_minus_tau")
  )
  pinball <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "pinball_summary.csv",
    c("scenario_id", "method", "tau", "pinball_mean")
  )
  wis <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "wis_summary.csv",
    c("scenario_id", "method", "wis_mean")
  )
  crps <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "crps_grid_summary.csv",
    c("scenario_id", "method", "crps_grid_mean")
  )
  vb <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "vb_convergence_audit.csv",
    c("scenario_id", "origin_index", "refit", "status", "converged")
  )
  runtime <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "runtime_summary.csv",
    c("scenario_id", "origin_index", "elapsed_sec")
  )
  assessment <- app_joint_qvp_phase4g_read_phase3(
    phase3_dir,
    "forecast_validation_assessment.csv",
    c("scenario_id", "implementation_status", "gate_status", "total_crossing_pairs", "raw_crossing_pairs")
  )

  refit <- vb[app_as_bool_vec(vb$refit), , drop = FALSE]
  truth_vb <- truth[truth$method == "vb", , drop = FALSE]
  hit_vb <- hit[hit$method == "vb", , drop = FALSE]
  pinball_vb <- pinball[pinball$method == "vb", , drop = FALSE]
  wis_vb <- wis[wis$method == "vb", , drop = FALSE]
  crps_vb <- crps[crps$method == "vb", , drop = FALSE]

  data.frame(
    screen_id = screen_row$screen_id[[1L]],
    screen_class = screen_row$screen_class[[1L]],
    tau0 = screen_row$tau0[[1L]],
    zeta2 = screen_row$zeta2[[1L]],
    alpha_prior_sd = screen_row$alpha_prior_sd[[1L]],
    rhs_vb_inner = as.integer(screen_row$rhs_vb_inner[[1L]]),
    alpha_min_spacing = screen_row$alpha_min_spacing[[1L]],
    n_scenarios = length(unique(run_config$scenario_id)),
    n_forecast_origins = sum(run_config$n_forecast_origins),
    raw_crossing_pairs = sum(raw_crossing$n_crossing_pairs, na.rm = TRUE),
    raw_crossing_origins = sum(raw_crossing$n_crossing_pairs > 0L, na.rm = TRUE),
    raw_max_crossing_magnitude = if (nrow(raw_crossing)) max(raw_crossing$max_crossing_magnitude, na.rm = TRUE) else NA_real_,
    contract_crossing_pairs = sum(contract_crossing$n_crossing_pairs, na.rm = TRUE),
    contract_max_crossing_magnitude = if (nrow(contract_crossing)) max(contract_crossing$max_crossing_magnitude, na.rm = TRUE) else NA_real_,
    monotone_adjusted_origins = sum(adjustment$n_adjusted_quantiles > 0L, na.rm = TRUE),
    monotone_adjusted_quantiles = sum(adjustment$n_adjusted_quantiles, na.rm = TRUE),
    max_monotone_adjustment = if (nrow(adjustment)) max(adjustment$max_abs_adjustment, na.rm = TRUE) else NA_real_,
    truth_rmse_mean = mean(truth_vb$rmse_to_truth, na.rm = TRUE),
    truth_mae_mean = mean(truth_vb$mae_to_truth, na.rm = TRUE),
    truth_max_abs_error = if ("max_abs_error_to_truth" %in% names(truth_vb)) max(truth_vb$max_abs_error_to_truth, na.rm = TRUE) else NA_real_,
    max_abs_hit_rate_error = max(abs(hit_vb$hit_rate_minus_tau), na.rm = TRUE),
    mean_abs_hit_rate_error = mean(abs(hit_vb$hit_rate_minus_tau), na.rm = TRUE),
    pinball_mean = mean(pinball_vb$pinball_mean, na.rm = TRUE),
    wis_mean = mean(wis_vb$wis_mean, na.rm = TRUE),
    crps_grid_mean = mean(crps_vb$crps_grid_mean, na.rm = TRUE),
    vb_refit_count = nrow(refit),
    vb_max_iter_count = if (nrow(refit)) sum(as.character(refit$status) != "prototype_success") else 0L,
    vb_max_iter_rate = if (nrow(refit)) mean(as.character(refit$status) != "prototype_success") else NA_real_,
    runtime_total_sec = sum(runtime$elapsed_sec, na.rm = TRUE),
    runtime_refit_sec = if ("component" %in% names(runtime)) sum(runtime$elapsed_sec[runtime$component == "VB adaptive refit"], na.rm = TRUE) else NA_real_,
    scenario_pass_count = sum(assessment$gate_status == "pass", na.rm = TRUE),
    scenario_review_count = sum(assessment$gate_status == "review", na.rm = TRUE),
    scenario_fail_count = sum(assessment$gate_status == "fail", na.rm = TRUE),
    phase3_out_dir = app_prefer_repo_relative_path(phase3_dir),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4g_compare_to_baseline <- function(metric_summary, baseline_screen_id = "baseline_vb480") {
  if (!nrow(metric_summary)) return(data.frame())
  baseline <- metric_summary[metric_summary$screen_id == baseline_screen_id, , drop = FALSE]
  if (!nrow(baseline)) baseline <- metric_summary[1L, , drop = FALSE]
  out <- metric_summary
  out$baseline_screen_id <- baseline$screen_id[[1L]]
  out$raw_crossing_reduction_fraction <- if (is.finite(baseline$raw_crossing_pairs[[1L]]) && baseline$raw_crossing_pairs[[1L]] > 0) {
    (baseline$raw_crossing_pairs[[1L]] - out$raw_crossing_pairs) / baseline$raw_crossing_pairs[[1L]]
  } else {
    NA_real_
  }
  out$raw_magnitude_reduction_fraction <- if (is.finite(baseline$raw_max_crossing_magnitude[[1L]]) && baseline$raw_max_crossing_magnitude[[1L]] > 1.0e-12) {
    (baseline$raw_max_crossing_magnitude[[1L]] - out$raw_max_crossing_magnitude) / baseline$raw_max_crossing_magnitude[[1L]]
  } else {
    NA_real_
  }
  out$truth_mae_worsening_fraction <- if (is.finite(baseline$truth_mae_mean[[1L]]) && baseline$truth_mae_mean[[1L]] > 1.0e-12) {
    (out$truth_mae_mean - baseline$truth_mae_mean[[1L]]) / baseline$truth_mae_mean[[1L]]
  } else {
    out$truth_mae_mean - baseline$truth_mae_mean[[1L]]
  }
  out$hit_rate_error_delta <- out$max_abs_hit_rate_error - baseline$max_abs_hit_rate_error[[1L]]
  out$runtime_ratio <- if (is.finite(baseline$runtime_total_sec[[1L]]) && baseline$runtime_total_sec[[1L]] > 1.0e-12) {
    out$runtime_total_sec / baseline$runtime_total_sec[[1L]]
  } else {
    NA_real_
  }
  out$vb_max_iter_rate_delta <- out$vb_max_iter_rate - baseline$vb_max_iter_rate[[1L]]
  finite_required <- is.finite(out$raw_crossing_pairs) &
    is.finite(out$contract_crossing_pairs) &
    is.finite(out$truth_mae_mean) &
    is.finite(out$max_abs_hit_rate_error)
  contract_ok <- out$contract_crossing_pairs == 0
  raw_improved <- (is.finite(out$raw_crossing_reduction_fraction) & out$raw_crossing_reduction_fraction >= 0.50) |
    (is.finite(out$raw_magnitude_reduction_fraction) & out$raw_magnitude_reduction_fraction >= 0.50)
  truth_ok <- !is.finite(out$truth_mae_worsening_fraction) | out$truth_mae_worsening_fraction <= 0.02
  hit_ok <- !is.finite(out$hit_rate_error_delta) | out$hit_rate_error_delta <= 0.025
  vb_limit <- max(c(baseline$vb_max_iter_rate[[1L]], 0.25), na.rm = TRUE)
  vb_ok <- !is.finite(out$vb_max_iter_rate) | out$vb_max_iter_rate <= vb_limit
  runtime_ok <- !is.finite(out$runtime_ratio) | out$runtime_ratio <= 2
  out$screen_status <- vapply(seq_len(nrow(out)), function(ii) {
    if (identical(out$screen_id[[ii]], baseline$screen_id[[1L]])) return("reference")
    if (!finite_required[[ii]] || !contract_ok[[ii]]) return("fail")
    if (raw_improved[[ii]] && truth_ok[[ii]] && hit_ok[[ii]] && vb_ok[[ii]] && runtime_ok[[ii]]) {
      return("promote_to_calibration_pilot")
    }
    "review"
  }, character(1L))
  truth_penalty <- ifelse(is.finite(out$truth_mae_worsening_fraction), pmax(out$truth_mae_worsening_fraction, 0), 0)
  runtime_penalty <- ifelse(is.finite(out$runtime_ratio), pmax(out$runtime_ratio, 0), 0)
  out$ranking_score <- 1000 * pmax(out$raw_crossing_pairs, 0) +
    100 * pmax(out$raw_max_crossing_magnitude, 0) +
    10 * truth_penalty +
    pmax(out$max_abs_hit_rate_error, 0) +
    pmax(out$vb_max_iter_rate, 0) +
    0.01 * runtime_penalty
  out$ranking_score[!is.finite(out$ranking_score)] <- Inf
  out$rank <- rank(out$ranking_score, ties.method = "first")
  out$note <- vapply(seq_len(nrow(out)), function(ii) {
    app_joint_qvp_ts_assessment_note(c(
      if (out$screen_status[[ii]] == "reference") "baseline reference",
      if (!finite_required[[ii]]) "nonfinite required screen metric",
      if (!contract_ok[[ii]]) "contract forecast crossing",
      if (raw_improved[[ii]]) "raw crossing reduction reached screening rule",
      if (out$screen_status[[ii]] == "review" && !raw_improved[[ii]]) "raw crossing promotion rule not met",
      if (!truth_ok[[ii]]) "truth MAE worsened beyond screening tolerance",
      if (!hit_ok[[ii]]) "hit-rate error worsened beyond screening tolerance",
      if (!vb_ok[[ii]]) "VB max-iteration rate review",
      if (!runtime_ok[[ii]]) "runtime ratio review"
    ))
  }, character(1L))
  out[order(out$rank), , drop = FALSE]
}

app_joint_qvp_phase4g_recommendation <- function(candidate_ranking, out_dir, tier) {
  promoted <- candidate_ranking[candidate_ranking$screen_status == "promote_to_calibration_pilot", , drop = FALSE]
  failing_contract <- candidate_ranking[candidate_ranking$contract_crossing_pairs > 0, , drop = FALSE]
  best <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE][1L, , drop = FALSE]
  status <- if (nrow(promoted)) {
    best <- promoted[order(promoted$ranking_score), , drop = FALSE][1L, , drop = FALSE]
    "promote_best_to_calibration_pilot"
  } else if (nrow(failing_contract)) {
    "blocked_contract_crossing"
  } else {
    "no_promoted_candidate_keep_contract_policy_or_expand_tier2"
  }
  next_command <- paste(
    "Rscript application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R",
    "--tier targeted",
    sprintf("--screen-ids %s", best$screen_id[[1L]]),
    sprintf("--output-dir %s", file.path(out_dir, paste0("pilot_", best$screen_id[[1L]])))
  )
  data.frame(
    scope = "phase4g_prior_design_screen",
    tier = tier,
    gate_status = if (nrow(failing_contract)) "fail" else "review",
    recommendation_status = status,
    best_screen_id = best$screen_id[[1L]],
    best_screen_status = best$screen_status[[1L]],
    best_raw_crossing_pairs = best$raw_crossing_pairs[[1L]],
    best_contract_crossing_pairs = best$contract_crossing_pairs[[1L]],
    best_truth_mae_mean = best$truth_mae_mean[[1L]],
    best_vb_max_iter_rate = best$vb_max_iter_rate[[1L]],
    recommended_next_command = next_command,
    note = app_joint_qvp_ts_assessment_note(c(
      if (nrow(promoted)) "at least one prior/design screen reduced raw crossings without exceeding conservative screening tolerances",
      if (!nrow(promoted)) "no screen met promotion criteria; keep raw/contract policy and consider tier-2 design work",
      if (nrow(failing_contract)) "at least one screen produced contract crossings and blocks promotion"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4g_readme_lines <- function(run_config, recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Phase 4g Prior/Design Screen",
    "",
    "This artifact directory screens targeted RHS prior and small design controls on the frozen Phase 4c crossing-registry rows.",
    "Each screen reuses the Phase 3 raw/contract forecast policy: raw forecast quantiles remain diagnostic, while monotone contract quantiles are used for scoring.",
    "",
    sprintf("- Tier: %s", run_config$tier[[1L]]),
    sprintf("- Targeted registry rows: %s", run_config$n_targeted_registry_rows[[1L]]),
    sprintf("- Screen rows: %s", run_config$n_screen_rows[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    "",
    "Primary files:",
    "",
    "- `targeted_registry.csv`: frozen targeted replicated scenario rows used by every screen.",
    "- `screen_grid.csv`: candidate prior/design controls.",
    "- `screen_run_config.csv`: run controls and fixture/Phase 3 directories.",
    "- `screen_metric_summary.csv`: raw/contract crossings, truth scores, hit errors, convergence, and runtime by screen.",
    "- `screen_candidate_ranking.csv`: conservative comparison to baseline and promotion/review/fail status.",
    "- `screen_run_manifest.csv`: Phase 3 manifest hash verification for each screen.",
    "- `screen_recommendation.csv`: recommended next action.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 4g root artifacts."
  )
}

app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_phase4g_screen_dir(),
  targeted_registry_path = app_joint_qvp_default_synthetic_dgp_phase4g_targeted_registry_path(),
  targeted_registry = NULL,
  tier = c("smoke", "targeted"),
  screen_grid = NULL,
  screen_ids = NULL,
  scenario_ids = NULL,
  vb_max_iter = NULL,
  adaptive_vb_max_iter_grid = NULL,
  refit_stride = NULL,
  forecast_origin_stride = NULL,
  max_origins_per_scenario = NULL,
  vb_tol = 1.0e-4,
  kappa = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  baseline_screen_id = "baseline_vb480"
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "targeted"))
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  defaults <- if (identical(tier, "smoke")) {
    list(vb_max_iter = 12L, adaptive_vb_max_iter_grid = c(12L, 24L), refit_stride = 99L, forecast_origin_stride = 20L, max_origins_per_scenario = 2L)
  } else {
    list(vb_max_iter = 480L, adaptive_vb_max_iter_grid = c(480L, 720L), refit_stride = 20L, forecast_origin_stride = 10L, max_origins_per_scenario = 40L)
  }
  vb_max_iter <- as.integer(vb_max_iter %||% defaults$vb_max_iter)
  adaptive_vb_max_iter_grid <- app_joint_qvp_normalize_vb_max_iter_grid(
    vb_max_iter,
    adaptive_vb_max_iter_grid %||% defaults$adaptive_vb_max_iter_grid
  )
  refit_stride <- as.integer(refit_stride %||% defaults$refit_stride)
  forecast_origin_stride <- as.integer(forecast_origin_stride %||% defaults$forecast_origin_stride)
  max_origins_per_scenario <- max_origins_per_scenario %||% defaults$max_origins_per_scenario
  targeted_registry <- app_joint_qvp_phase4g_load_targeted_registry(
    targeted_registry_path = targeted_registry_path,
    targeted_registry = targeted_registry,
    scenario_ids = scenario_ids,
    tier = tier
  )
  screen_grid <- if (is.null(screen_grid)) {
    app_joint_qvp_phase4g_screen_grid(tier = tier, screen_ids = screen_ids)
  } else {
    grid <- app_joint_qvp_validate_phase4_screen_grid(screen_grid, "custom Phase 4 screen grid")
    if (!is.null(screen_ids) && length(screen_ids)) {
      screen_ids <- unique(as.character(screen_ids))
      screen_ids <- screen_ids[nzchar(screen_ids)]
      missing_ids <- setdiff(screen_ids, grid$screen_id)
      if (length(missing_ids)) {
        stop("Requested custom Phase 4 screen id(s) not found: ", paste(missing_ids, collapse = ", "), call. = FALSE)
      }
      grid <- grid[match(screen_ids, grid$screen_id), , drop = FALSE]
    }
    rownames(grid) <- NULL
    grid
  }

  fixture_dir <- file.path(out_dir, "phase1_fixtures_targeted")
  app_joint_qvp_materialize_synthetic_dgp_registry(out_dir = fixture_dir, registry = targeted_registry)
  fixture_manifest <- app_joint_qvp_phase4_manifest_with_hashes(fixture_dir)
  if (!all(fixture_manifest$hash_verified)) stop("Phase 4g targeted fixture manifest failed hash verification.", call. = FALSE)

  run_rows <- list()
  metric_rows <- list()
  manifest_rows <- list()
  for (ii in seq_len(nrow(screen_grid))) {
    screen <- screen_grid[ii, , drop = FALSE]
    phase3_dir <- file.path(out_dir, "screen_runs", screen$screen_id[[1L]])
    phase3_result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
      out_dir = phase3_dir,
      fixture_dir = fixture_dir,
      scenario_ids = targeted_registry$scenario_id,
      kappa = kappa,
      tau0 = screen$tau0[[1L]],
      zeta2 = screen$zeta2[[1L]],
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = screen$alpha_prior_sd[[1L]],
      alpha_min_spacing = screen$alpha_min_spacing[[1L]],
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      rhs_vb_inner = as.integer(screen$rhs_vb_inner[[1L]]),
      refit_stride = refit_stride,
      forecast_origin_stride = forecast_origin_stride,
      max_origins_per_scenario = max_origins_per_scenario,
      vb_tol = vb_tol
    )
    phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_result$out_dir)
    metric_rows[[length(metric_rows) + 1L]] <- app_joint_qvp_phase4g_screen_metrics(phase3_result$out_dir, screen)
    manifest_rows[[length(manifest_rows) + 1L]] <- data.frame(
      screen_id = screen$screen_id[[1L]],
      phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
      phase3_artifact_manifest = app_prefer_repo_relative_path(phase3_result$paths[["artifact_manifest"]]),
      n_manifest_rows = nrow(phase3_manifest),
      manifest_hashes_verified = all(phase3_manifest$hash_verified),
      manifest_sha256 = app_sha256_file(phase3_result$paths[["artifact_manifest"]]),
      stringsAsFactors = FALSE
    )
    run_rows[[length(run_rows) + 1L]] <- data.frame(
      screen_id = screen$screen_id[[1L]],
      screen_class = screen$screen_class[[1L]],
      tau0 = screen$tau0[[1L]],
      zeta2 = screen$zeta2[[1L]],
      alpha_prior_sd = screen$alpha_prior_sd[[1L]],
      rhs_vb_inner = as.integer(screen$rhs_vb_inner[[1L]]),
      alpha_min_spacing = screen$alpha_min_spacing[[1L]],
      phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
      stringsAsFactors = FALSE
    )
  }

  screen_run_manifest <- do.call(rbind, manifest_rows)
  screen_metric_summary <- do.call(rbind, metric_rows)
  screen_candidate_ranking <- app_joint_qvp_phase4g_compare_to_baseline(screen_metric_summary, baseline_screen_id = baseline_screen_id)
  screen_crossing_summary <- screen_candidate_ranking[, c(
    "screen_id", "screen_class", "raw_crossing_pairs", "raw_crossing_origins",
    "raw_max_crossing_magnitude", "contract_crossing_pairs", "contract_max_crossing_magnitude",
    "monotone_adjusted_origins", "max_monotone_adjustment", "screen_status", "note"
  ), drop = FALSE]
  screen_truth_metric_summary <- screen_candidate_ranking[, c(
    "screen_id", "truth_rmse_mean", "truth_mae_mean", "truth_max_abs_error",
    "max_abs_hit_rate_error", "mean_abs_hit_rate_error", "pinball_mean", "wis_mean",
    "crps_grid_mean", "truth_mae_worsening_fraction", "hit_rate_error_delta", "screen_status"
  ), drop = FALSE]
  screen_vb_runtime_summary <- screen_candidate_ranking[, c(
    "screen_id", "vb_refit_count", "vb_max_iter_count", "vb_max_iter_rate",
    "vb_max_iter_rate_delta", "runtime_total_sec", "runtime_refit_sec", "runtime_ratio",
    "screen_status"
  ), drop = FALSE]
  screen_recommendation <- app_joint_qvp_phase4g_recommendation(screen_candidate_ranking, out_dir, tier)
  screen_run_config <- data.frame(
    tier = tier,
    targeted_registry_path = if (is.null(targeted_registry_path)) NA_character_ else app_prefer_repo_relative_path(targeted_registry_path),
    targeted_registry_sha256 = if (!is.null(targeted_registry_path) && file.exists(targeted_registry_path)) app_sha256_file(targeted_registry_path) else NA_character_,
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    fixture_manifest_sha256 = app_sha256_file(file.path(fixture_dir, "artifact_manifest.csv")),
    n_targeted_registry_rows = nrow(targeted_registry),
    n_screen_rows = nrow(screen_grid),
    baseline_screen_id = baseline_screen_id,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(adaptive_vb_max_iter_grid, collapse = ","),
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = if (is.finite(as.numeric(max_origins_per_scenario))) as.integer(max_origins_per_scenario) else NA_integer_,
    vb_tol = vb_tol,
    kappa = kappa,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    all_phase3_manifest_hashes_verified = all(screen_run_manifest$manifest_hashes_verified),
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase4g_readme_lines(screen_run_config, screen_recommendation), readme_path, useBytes = TRUE)
  paths <- c(
    targeted_registry = app_joint_qvp_write_csv(targeted_registry, file.path(out_dir, "targeted_registry.csv")),
    screen_grid = app_joint_qvp_write_csv(screen_grid, file.path(out_dir, "screen_grid.csv")),
    screen_run_config = app_joint_qvp_write_csv(screen_run_config, file.path(out_dir, "screen_run_config.csv")),
    screen_metric_summary = app_joint_qvp_write_csv(screen_metric_summary, file.path(out_dir, "screen_metric_summary.csv")),
    screen_candidate_ranking = app_joint_qvp_write_csv(screen_candidate_ranking, file.path(out_dir, "screen_candidate_ranking.csv")),
    screen_crossing_summary = app_joint_qvp_write_csv(screen_crossing_summary, file.path(out_dir, "screen_crossing_summary.csv")),
    screen_truth_metric_summary = app_joint_qvp_write_csv(screen_truth_metric_summary, file.path(out_dir, "screen_truth_metric_summary.csv")),
    screen_vb_runtime_summary = app_joint_qvp_write_csv(screen_vb_runtime_summary, file.path(out_dir, "screen_vb_runtime_summary.csv")),
    screen_run_manifest = app_joint_qvp_write_csv(screen_run_manifest, file.path(out_dir, "screen_run_manifest.csv")),
    screen_recommendation = app_joint_qvp_write_csv(screen_recommendation, file.path(out_dir, "screen_recommendation.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    fixture_dir = fixture_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    targeted_registry = targeted_registry,
    screen_grid = screen_grid,
    screen_run_config = screen_run_config,
    screen_metric_summary = screen_metric_summary,
    screen_candidate_ranking = screen_candidate_ranking,
    screen_recommendation = screen_recommendation
  )
}

app_joint_qvp_phase4h_phase3_dir <- function(path) {
  path <- as.character(path)[[1L]]
  if (grepl("^/", path)) normalizePath(path, mustWork = TRUE) else normalizePath(app_path(path), mustWork = TRUE)
}

app_joint_qvp_phase4h_screen_row <- function(screen_grid, screen_id) {
  row <- screen_grid[screen_grid$screen_id == screen_id, , drop = FALSE]
  if (!nrow(row)) stop("Missing Phase 4h screen row for ", screen_id, ".", call. = FALSE)
  row[1L, , drop = FALSE]
}

app_joint_qvp_phase4h_crossing_by_scenario <- function(screen_run_manifest, screen_grid, targeted_registry) {
  rows <- list()
  for (ii in seq_len(nrow(screen_run_manifest))) {
    screen_id <- screen_run_manifest$screen_id[[ii]]
    screen <- app_joint_qvp_phase4h_screen_row(screen_grid, screen_id)
    phase3_dir <- app_joint_qvp_phase4h_phase3_dir(screen_run_manifest$phase3_out_dir[[ii]])
    cfg <- app_read_csv(file.path(phase3_dir, "run_config.csv"))
    raw <- app_read_csv(file.path(phase3_dir, "raw_crossing_summary.csv"))
    contract <- app_read_csv(file.path(phase3_dir, "crossing_summary.csv"))
    adj <- app_read_csv(file.path(phase3_dir, "forecast_monotone_adjustment.csv"))
    for (scenario_id in unique(cfg$scenario_id)) {
      cfg_i <- cfg[cfg$scenario_id == scenario_id, , drop = FALSE][1L, , drop = FALSE]
      reg_i <- targeted_registry[targeted_registry$scenario_id == scenario_id, , drop = FALSE]
      raw_i <- raw[raw$scenario_id == scenario_id, , drop = FALSE]
      contract_i <- contract[contract$scenario_id == scenario_id, , drop = FALSE]
      adj_i <- adj[adj$scenario_id == scenario_id, , drop = FALSE]
      rows[[length(rows) + 1L]] <- data.frame(
        screen_id = screen_id,
        screen_class = screen$screen_class[[1L]],
        tau0 = screen$tau0[[1L]],
        zeta2 = screen$zeta2[[1L]],
        alpha_prior_sd = screen$alpha_prior_sd[[1L]],
        rhs_vb_inner = as.integer(screen$rhs_vb_inner[[1L]]),
        scenario_id = scenario_id,
        base_scenario_id = if (nrow(reg_i) && "base_scenario_id" %in% names(reg_i)) reg_i$base_scenario_id[[1L]] else scenario_id,
        replicate_id = if (nrow(reg_i) && "replicate_id" %in% names(reg_i)) reg_i$replicate_id[[1L]] else NA_integer_,
        scenario_class = cfg_i$scenario_class[[1L]],
        distribution_family = cfg_i$distribution_family[[1L]],
        dynamics_class = cfg_i$dynamics_class[[1L]],
        raw_crossing_pairs = sum(raw_i$n_crossing_pairs, na.rm = TRUE),
        raw_crossing_origins = sum(raw_i$n_crossing_pairs > 0L, na.rm = TRUE),
        raw_max_crossing_magnitude = if (nrow(raw_i)) max(raw_i$max_crossing_magnitude, na.rm = TRUE) else 0,
        contract_crossing_pairs = sum(contract_i$n_crossing_pairs, na.rm = TRUE),
        contract_crossing_origins = sum(contract_i$n_crossing_pairs > 0L, na.rm = TRUE),
        contract_max_crossing_magnitude = if (nrow(contract_i)) max(contract_i$max_crossing_magnitude, na.rm = TRUE) else 0,
        monotone_adjusted_origins = sum(adj_i$n_adjusted_quantiles > 0L, na.rm = TRUE),
        max_monotone_adjustment = if (nrow(adj_i)) max(adj_i$max_abs_adjustment, na.rm = TRUE) else 0,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

app_joint_qvp_phase4h_pair_events <- function(forecast_raw, screen) {
  split_key <- paste(
    forecast_raw$scenario_id,
    forecast_raw$origin_index,
    forecast_raw$forecast_time_index,
    sep = "\r"
  )
  groups <- split(forecast_raw, split_key, drop = TRUE)
  rows <- lapply(groups, function(g) {
    g <- g[order(g$quantile_index), , drop = FALSE]
    if (nrow(g) < 2L) return(NULL)
    lower <- g[-nrow(g), , drop = FALSE]
    upper <- g[-1L, , drop = FALSE]
    magnitude <- pmax(lower$qhat - upper$qhat, 0)
    data.frame(
      screen_id = screen$screen_id[[1L]],
      screen_class = screen$screen_class[[1L]],
      tau0 = screen$tau0[[1L]],
      zeta2 = screen$zeta2[[1L]],
      alpha_prior_sd = screen$alpha_prior_sd[[1L]],
      rhs_vb_inner = as.integer(screen$rhs_vb_inner[[1L]]),
      scenario_id = lower$scenario_id,
      origin_index = lower$origin_index,
      forecast_time_index = lower$forecast_time_index,
      lower_tau = lower$tau,
      upper_tau = upper$tau,
      lower_qhat = lower$qhat,
      upper_qhat = upper$qhat,
      true_lower_quantile = lower$true_quantile,
      true_upper_quantile = upper$true_quantile,
      true_gap = upper$true_quantile - lower$true_quantile,
      crossing_pair = magnitude > 0,
      crossing_magnitude = magnitude,
      stringsAsFactors = FALSE
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

app_joint_qvp_phase4h_crossing_by_tau_pair <- function(screen_run_manifest, screen_grid) {
  event_rows <- list()
  for (ii in seq_len(nrow(screen_run_manifest))) {
    screen_id <- screen_run_manifest$screen_id[[ii]]
    screen <- app_joint_qvp_phase4h_screen_row(screen_grid, screen_id)
    phase3_dir <- app_joint_qvp_phase4h_phase3_dir(screen_run_manifest$phase3_out_dir[[ii]])
    raw <- app_read_csv(file.path(phase3_dir, "forecast_quantiles_raw.csv"))
    event_rows[[length(event_rows) + 1L]] <- app_joint_qvp_phase4h_pair_events(raw, screen)
  }
  events <- do.call(rbind, event_rows)
  if (!nrow(events)) return(data.frame())
  key <- paste(events$screen_id, events$lower_tau, events$upper_tau, sep = "\r")
  groups <- split(events, key, drop = TRUE)
  rows <- lapply(groups, function(g) {
    data.frame(
      screen_id = g$screen_id[[1L]],
      screen_class = g$screen_class[[1L]],
      tau0 = g$tau0[[1L]],
      zeta2 = g$zeta2[[1L]],
      alpha_prior_sd = g$alpha_prior_sd[[1L]],
      rhs_vb_inner = as.integer(g$rhs_vb_inner[[1L]]),
      lower_tau = g$lower_tau[[1L]],
      upper_tau = g$upper_tau[[1L]],
      n_origins = nrow(g),
      raw_crossing_pairs = sum(g$crossing_pair, na.rm = TRUE),
      raw_crossing_origins = sum(g$crossing_pair, na.rm = TRUE),
      raw_max_crossing_magnitude = if (nrow(g)) max(g$crossing_magnitude, na.rm = TRUE) else 0,
      mean_true_gap = mean(g$true_gap, na.rm = TRUE),
      min_true_gap = min(g$true_gap, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(out$screen_id, out$lower_tau), , drop = FALSE]
}

app_joint_qvp_phase4h_truth_by_tau <- function(screen_run_manifest, screen_grid) {
  rows <- list()
  for (ii in seq_len(nrow(screen_run_manifest))) {
    screen_id <- screen_run_manifest$screen_id[[ii]]
    screen <- app_joint_qvp_phase4h_screen_row(screen_grid, screen_id)
    phase3_dir <- app_joint_qvp_phase4h_phase3_dir(screen_run_manifest$phase3_out_dir[[ii]])
    truth <- app_read_csv(file.path(phase3_dir, "forecast_truth_comparison.csv"))
    truth <- truth[truth$method == "vb", , drop = FALSE]
    groups <- split(truth, truth$tau, drop = TRUE)
    rows <- c(rows, lapply(groups, function(g) {
      data.frame(
        screen_id = screen_id,
        screen_class = screen$screen_class[[1L]],
        tau0 = screen$tau0[[1L]],
        zeta2 = screen$zeta2[[1L]],
        alpha_prior_sd = screen$alpha_prior_sd[[1L]],
        rhs_vb_inner = as.integer(screen$rhs_vb_inner[[1L]]),
        tau = g$tau[[1L]],
        n_scenarios = length(unique(g$scenario_id)),
        n_forecasts = sum(g$n_forecasts, na.rm = TRUE),
        rmse_to_truth_mean = mean(g$rmse_to_truth, na.rm = TRUE),
        mae_to_truth_mean = mean(g$mae_to_truth, na.rm = TRUE),
        bias_to_truth_mean = mean(g$bias_to_truth, na.rm = TRUE),
        max_abs_error_to_truth = max(g$max_abs_error_to_truth, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    }))
  }
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  out[order(out$screen_id, out$tau), , drop = FALSE]
}

app_joint_qvp_phase4h_recommendation <- function(
  candidate_ranking,
  crossing_by_tau_pair,
  reference_screen_id = "tau0_0p10_reference"
) {
  failing_contract <- candidate_ranking[candidate_ranking$contract_crossing_pairs > 0, , drop = FALSE]
  ref <- candidate_ranking[candidate_ranking$screen_id == reference_screen_id, , drop = FALSE]
  if (!nrow(ref)) ref <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE][1L, , drop = FALSE]
  ordered <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE]
  best <- ordered[1L, , drop = FALSE]
  upper <- crossing_by_tau_pair[
    abs(crossing_by_tau_pair$lower_tau - 0.90) < 1.0e-10 &
      abs(crossing_by_tau_pair$upper_tau - 0.95) < 1.0e-10,
    , drop = FALSE
  ]
  ref_upper <- upper$raw_crossing_pairs[upper$screen_id == ref$screen_id[[1L]]]
  best_upper <- upper$raw_crossing_pairs[upper$screen_id == best$screen_id[[1L]]]
  ref_upper <- if (length(ref_upper)) ref_upper[[1L]] else NA_real_
  best_upper <- if (length(best_upper)) best_upper[[1L]] else NA_real_
  improves_raw <- is.finite(best$raw_crossing_pairs[[1L]]) &&
    is.finite(ref$raw_crossing_pairs[[1L]]) &&
    best$raw_crossing_pairs[[1L]] < ref$raw_crossing_pairs[[1L]]
  competitive_truth <- is.finite(best$truth_mae_mean[[1L]]) &&
    is.finite(ref$truth_mae_mean[[1L]]) &&
    best$truth_mae_mean[[1L]] <= 1.01 * ref$truth_mae_mean[[1L]]
  upper_ok <- !is.finite(best_upper) || !is.finite(ref_upper) || best_upper <= ref_upper
  vb_ok <- !is.finite(best$vb_max_iter_rate[[1L]]) || best$vb_max_iter_rate[[1L]] <= 0.20
  runtime_ok <- !is.finite(best$runtime_ratio[[1L]]) || best$runtime_ratio[[1L]] <= 1.25
  candidate_ready <- !nrow(failing_contract) &&
    best$contract_crossing_pairs[[1L]] == 0 &&
    (improves_raw || best$screen_id[[1L]] == ref$screen_id[[1L]]) &&
    competitive_truth && upper_ok && vb_ok && runtime_ok
  recommendation_status <- if (nrow(failing_contract)) {
    "blocked_contract_crossing"
  } else if (candidate_ready && best$screen_id[[1L]] != ref$screen_id[[1L]]) {
    "candidate_ready_for_calibration_pilot"
  } else if (candidate_ready) {
    "reference_remains_candidate_for_calibration_pilot"
  } else {
    "review_no_phase4h_candidate_ready"
  }
  data.frame(
    scope = "phase4h_tau0_refinement",
    gate_status = if (nrow(failing_contract)) "fail" else "review",
    recommendation_status = recommendation_status,
    reference_screen_id = ref$screen_id[[1L]],
    best_screen_id = best$screen_id[[1L]],
    best_raw_crossing_pairs = best$raw_crossing_pairs[[1L]],
    reference_raw_crossing_pairs = ref$raw_crossing_pairs[[1L]],
    best_upper_tail_crossing_pairs = best_upper,
    reference_upper_tail_crossing_pairs = ref_upper,
    best_contract_crossing_pairs = best$contract_crossing_pairs[[1L]],
    best_truth_mae_mean = best$truth_mae_mean[[1L]],
    reference_truth_mae_mean = ref$truth_mae_mean[[1L]],
    best_vb_max_iter_rate = best$vb_max_iter_rate[[1L]],
    best_runtime_ratio = best$runtime_ratio[[1L]],
    note = app_joint_qvp_ts_assessment_note(c(
      if (nrow(failing_contract)) "contract crossings block Phase 4h promotion",
      if (!nrow(failing_contract)) "contract crossings remain zero under the raw/contract policy",
      if (improves_raw) "best candidate improves raw crossing count relative to the Phase 4h reference",
      if (!improves_raw && best$screen_id[[1L]] != ref$screen_id[[1L]]) "best candidate does not improve raw crossings relative to reference",
      if (!upper_ok) "upper-tail 0.90-0.95 crossing count review",
      if (!competitive_truth) "truth MAE review",
      if (!vb_ok) "VB max-iteration rate review",
      if (!runtime_ok) "runtime ratio review",
      "Phase 4h can only recommend a calibration pilot, not a final default change"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4h_readme_lines <- function(run_config, recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Phase 4h Tau0 Refinement",
    "",
    "This artifact directory refines the RHS global shrinkage parameter tau0 on the frozen Phase 4c targeted crossing registry.",
    "It reuses the Phase 3 raw/contract forecast policy and the Phase 4g screen aggregation path.",
    "",
    sprintf("- Targeted registry rows: %s", run_config$n_targeted_registry_rows[[1L]]),
    sprintf("- Screen rows: %s", run_config$n_screen_rows[[1L]]),
    sprintf("- Reference screen id: %s", run_config$reference_screen_id[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    "",
    "Primary files:",
    "",
    "- `targeted_registry.csv`: exact frozen replicated rows and seeds.",
    "- `tau0_refinement_grid.csv`: tau0-local candidate grid.",
    "- `tau0_refinement_run_config.csv`: run controls and source hashes.",
    "- `tau0_refinement_metric_summary.csv`: raw/contract crossings, truth scores, hit errors, convergence, and runtime by screen.",
    "- `tau0_refinement_candidate_ranking.csv`: conservative ranking relative to the Phase 4h reference.",
    "- `tau0_refinement_crossing_by_scenario.csv`: scenario-level raw/contract crossing diagnostics.",
    "- `tau0_refinement_crossing_by_tau_pair.csv`: adjacent tau-pair raw crossing diagnostics.",
    "- `tau0_refinement_truth_by_tau.csv`: truth-distance diagnostics by tau.",
    "- `tau0_refinement_vb_runtime_summary.csv`: VB refit/runtime diagnostics.",
    "- `tau0_refinement_recommendation.csv`: candidate/readiness recommendation.",
    "- `screen_run_manifest.csv`: nested Phase 3 artifact manifest verification.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 4h root artifacts.",
    "",
    "Interpretation:",
    "",
    "Phase 4h is a targeted local refinement screen. It can recommend a candidate for a calibration pilot, but it cannot by itself promote article-candidate defaults."
  )
}

app_joint_qvp_run_synthetic_dgp_phase4h_tau0_refinement <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_phase4h_screen_dir(),
  targeted_registry_path = app_joint_qvp_default_synthetic_dgp_phase4g_targeted_registry_path(),
  targeted_registry = NULL,
  tau0_grid = c(0.25, 0.20, 0.15, 0.10, 0.075, 0.05),
  include_secondary_grid = FALSE,
  screen_ids = NULL,
  scenario_ids = NULL,
  tier = c("targeted", "smoke"),
  vb_max_iter = NULL,
  adaptive_vb_max_iter_grid = NULL,
  refit_stride = NULL,
  forecast_origin_stride = NULL,
  max_origins_per_scenario = NULL,
  vb_tol = 1.0e-4,
  kappa = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  reference_screen_id = NULL
) {
  tier <- match.arg(as.character(tier)[[1L]], c("targeted", "smoke"))
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  screen_grid <- app_joint_qvp_phase4h_tau0_screen_grid(
    tau0_grid = tau0_grid,
    include_secondary_grid = include_secondary_grid,
    screen_ids = screen_ids
  )
  if (is.null(reference_screen_id)) {
    reference_screen_id <- if ("tau0_0p10_reference" %in% screen_grid$screen_id) {
      "tau0_0p10_reference"
    } else if ("tau0_0p25_reference" %in% screen_grid$screen_id) {
      "tau0_0p25_reference"
    } else {
      screen_grid$screen_id[[1L]]
    }
  }
  if (!reference_screen_id %in% screen_grid$screen_id) {
    stop("Phase 4h reference_screen_id is not present in the tau0 refinement grid.", call. = FALSE)
  }
  result <- app_joint_qvp_run_synthetic_dgp_phase4g_prior_design_screen(
    out_dir = out_dir,
    targeted_registry_path = targeted_registry_path,
    targeted_registry = targeted_registry,
    tier = tier,
    screen_grid = screen_grid,
    scenario_ids = scenario_ids,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = max_origins_per_scenario,
    vb_tol = vb_tol,
    kappa = kappa,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    baseline_screen_id = reference_screen_id
  )
  screen_run_manifest <- app_read_csv(file.path(out_dir, "screen_run_manifest.csv"))
  crossing_by_scenario <- app_joint_qvp_phase4h_crossing_by_scenario(
    screen_run_manifest,
    result$screen_grid,
    result$targeted_registry
  )
  crossing_by_tau_pair <- app_joint_qvp_phase4h_crossing_by_tau_pair(screen_run_manifest, result$screen_grid)
  truth_by_tau <- app_joint_qvp_phase4h_truth_by_tau(screen_run_manifest, result$screen_grid)
  vb_runtime_summary <- result$screen_candidate_ranking[, c(
    "screen_id", "screen_class", "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner",
    "vb_refit_count", "vb_max_iter_count", "vb_max_iter_rate", "vb_max_iter_rate_delta",
    "runtime_total_sec", "runtime_refit_sec", "runtime_ratio", "screen_status"
  ), drop = FALSE]
  recommendation <- app_joint_qvp_phase4h_recommendation(
    result$screen_candidate_ranking,
    crossing_by_tau_pair,
    reference_screen_id = reference_screen_id
  )
  run_config <- app_read_csv(file.path(out_dir, "screen_run_config.csv"))
  run_config$phase <- "phase4h_tau0_refinement"
  run_config$reference_screen_id <- reference_screen_id
  run_config$tau0_grid <- paste(tau0_grid, collapse = ",")
  run_config$include_secondary_grid <- isTRUE(include_secondary_grid)
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase4h_readme_lines(run_config, recommendation), readme_path, useBytes = TRUE)
  paths <- c(
    targeted_registry = app_joint_qvp_write_csv(result$targeted_registry, file.path(out_dir, "targeted_registry.csv")),
    tau0_refinement_grid = app_joint_qvp_write_csv(result$screen_grid, file.path(out_dir, "tau0_refinement_grid.csv")),
    tau0_refinement_run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "tau0_refinement_run_config.csv")),
    tau0_refinement_metric_summary = app_joint_qvp_write_csv(result$screen_metric_summary, file.path(out_dir, "tau0_refinement_metric_summary.csv")),
    tau0_refinement_candidate_ranking = app_joint_qvp_write_csv(result$screen_candidate_ranking, file.path(out_dir, "tau0_refinement_candidate_ranking.csv")),
    tau0_refinement_crossing_by_scenario = app_joint_qvp_write_csv(crossing_by_scenario, file.path(out_dir, "tau0_refinement_crossing_by_scenario.csv")),
    tau0_refinement_crossing_by_tau_pair = app_joint_qvp_write_csv(crossing_by_tau_pair, file.path(out_dir, "tau0_refinement_crossing_by_tau_pair.csv")),
    tau0_refinement_truth_by_tau = app_joint_qvp_write_csv(truth_by_tau, file.path(out_dir, "tau0_refinement_truth_by_tau.csv")),
    tau0_refinement_vb_runtime_summary = app_joint_qvp_write_csv(vb_runtime_summary, file.path(out_dir, "tau0_refinement_vb_runtime_summary.csv")),
    tau0_refinement_recommendation = app_joint_qvp_write_csv(recommendation, file.path(out_dir, "tau0_refinement_recommendation.csv")),
    screen_run_manifest = normalizePath(file.path(out_dir, "screen_run_manifest.csv"), mustWork = TRUE),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    fixture_dir = result$fixture_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    targeted_registry = result$targeted_registry,
    tau0_refinement_grid = result$screen_grid,
    tau0_refinement_run_config = run_config,
    tau0_refinement_metric_summary = result$screen_metric_summary,
    tau0_refinement_candidate_ranking = result$screen_candidate_ranking,
    tau0_refinement_crossing_by_scenario = crossing_by_scenario,
    tau0_refinement_crossing_by_tau_pair = crossing_by_tau_pair,
    tau0_refinement_truth_by_tau = truth_by_tau,
    tau0_refinement_vb_runtime_summary = vb_runtime_summary,
    tau0_refinement_recommendation = recommendation
  )
}

app_joint_qvp_phase4i_tier_defaults <- function(tier = c("smoke", "calibration_pilot")) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "calibration_pilot"))
  if (identical(tier, "smoke")) {
    return(list(
      simulated_length = 72L,
      washout_length = 12L,
      train_length = 42L,
      test_length = 18L,
      n_replicates = 1L,
      seed_base = 202607400L,
      vb_max_iter = 12L,
      adaptive_vb_max_iter_grid = c(12L, 24L),
      refit_stride = 99L,
      forecast_origin_stride = 1L,
      max_origins_per_scenario = 2L
    ))
  }
  list(
    simulated_length = 1200L,
    washout_length = 300L,
    train_length = 500L,
    test_length = 400L,
    n_replicates = 3L,
    seed_base = 202607400L,
    vb_max_iter = 480L,
    adaptive_vb_max_iter_grid = c(480L, 720L),
    refit_stride = 20L,
    forecast_origin_stride = 10L,
    max_origins_per_scenario = 40L
  )
}

app_joint_qvp_phase4i_tau0_arm_grid <- function(
  tau0_arms = c(0.10, 0.15),
  include_reference_arm = FALSE,
  arm_ids = NULL
) {
  tau0_arms <- as.numeric(tau0_arms)
  tau0_arms <- tau0_arms[is.finite(tau0_arms) & tau0_arms > 0]
  if (isTRUE(include_reference_arm) && !any(abs(tau0_arms - 0.25) < 1.0e-12)) tau0_arms <- c(tau0_arms, 0.25)
  tau0_arms <- unique(tau0_arms)
  if (!length(tau0_arms)) stop("Phase 4i tau0 arm grid must contain positive finite values.", call. = FALSE)
  labels <- vapply(tau0_arms, app_joint_qvp_phase4_screen_id_number_label, character(1L))
  arm <- data.frame(
    arm_id = paste0("tau0_", labels),
    screen_id = paste0("tau0_", labels),
    screen_class = "tau0_candidate_calibration_pilot",
    tau0 = tau0_arms,
    zeta2 = Inf,
    alpha_prior_sd = 1,
    rhs_vb_inner = 5L,
    alpha_min_spacing = 0,
    arm_role = "candidate",
    rationale = sprintf("Phase 4i candidate calibration-pilot tau0 arm = %s.", tau0_arms),
    stringsAsFactors = FALSE
  )
  arm$arm_id[abs(arm$tau0 - 0.10) < 1.0e-12] <- "tau0_0p10_primary"
  arm$arm_role[arm$arm_id == "tau0_0p10_primary"] <- "primary"
  arm$rationale[arm$arm_id == "tau0_0p10_primary"] <- "Phase 4h primary candidate: best global truth MAE with zero contract crossings."
  arm$arm_id[abs(arm$tau0 - 0.15) < 1.0e-12] <- "tau0_0p15_comparator"
  arm$arm_role[arm$arm_id == "tau0_0p15_comparator"] <- "comparator"
  arm$rationale[arm$arm_id == "tau0_0p15_comparator"] <- "Phase 4h comparator: similar raw crossings with slightly better tau 0.95 MAE and lower runtime."
  arm$arm_id[abs(arm$tau0 - 0.25) < 1.0e-12] <- "tau0_0p25_reference"
  arm$arm_role[arm$arm_id == "tau0_0p25_reference"] <- "reference"
  arm$rationale[arm$arm_id == "tau0_0p25_reference"] <- "Historical stable tau0 reference retained only when requested."
  arm$screen_id <- arm$arm_id
  arm <- arm[order(match(arm$arm_role, c("primary", "comparator", "candidate", "reference")), arm$tau0), , drop = FALSE]
  arm <- app_joint_qvp_validate_phase4_screen_grid(arm, "Phase 4i tau0 candidate arm grid")
  arm$arm_id <- arm$screen_id
  arm$arm_role <- rep("candidate", nrow(arm))
  arm$arm_role[arm$arm_id == "tau0_0p10_primary"] <- "primary"
  arm$arm_role[arm$arm_id == "tau0_0p15_comparator"] <- "comparator"
  arm$arm_role[arm$arm_id == "tau0_0p25_reference"] <- "reference"
  if (!is.null(arm_ids) && length(arm_ids)) {
    arm_ids <- unique(as.character(arm_ids))
    arm_ids <- arm_ids[nzchar(arm_ids)]
    missing_ids <- setdiff(arm_ids, arm$arm_id)
    if (length(missing_ids)) {
      stop("Requested Phase 4i arm id(s) not found: ", paste(missing_ids, collapse = ", "), call. = FALSE)
    }
    arm <- arm[match(arm_ids, arm$arm_id), , drop = FALSE]
  }
  rownames(arm) <- NULL
  arm
}

app_joint_qvp_phase4i_build_candidate_registry <- function(
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL,
  scenario_ids = NULL,
  tier = c("smoke", "calibration_pilot"),
  n_replicates = NULL,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "calibration_pilot"))
  defaults <- app_joint_qvp_phase4i_tier_defaults(tier)
  phase4_tier <- if (identical(tier, "smoke")) "smoke" else "calibration"
  out <- app_joint_qvp_phase4_build_calibration_registry(
    registry_path = registry_path,
    registry = registry,
    scenario_ids = scenario_ids,
    tier = phase4_tier,
    n_replicates = as.integer(n_replicates %||% defaults$n_replicates),
    seed_base = as.integer(seed_base %||% defaults$seed_base),
    simulated_length = as.integer(simulated_length %||% defaults$simulated_length),
    washout_length = as.integer(washout_length %||% defaults$washout_length),
    train_length = as.integer(train_length %||% defaults$train_length),
    test_length = as.integer(test_length %||% defaults$test_length)
  )
  out$registry_version <- paste0("phase4i_", tier, "_20260704")
  out$validation_tier <- tier
  out$seed_role <- paste0(tier, "_replicate_seed")
  if (identical(tier, "calibration_pilot")) {
    out$scenario_id <- sub("__calibration_r", "__calibration_pilot_r", out$scenario_id, fixed = TRUE)
    out$notes <- sub(" Phase 4 calibration replicate ", " Phase 4i calibration-pilot replicate ", out$notes, fixed = TRUE)
  } else {
    out$notes <- paste0(out$notes, " Phase 4i smoke candidate-pilot row.")
  }
  rownames(out) <- NULL
  app_joint_qvp_validate_synthetic_dgp_registry(out)
  out
}

app_joint_qvp_phase4i_metric_summary <- function(arm_run_manifest, arm_grid) {
  rows <- list()
  for (ii in seq_len(nrow(arm_run_manifest))) {
    arm_id <- arm_run_manifest$arm_id[[ii]]
    arm <- app_joint_qvp_phase4h_screen_row(arm_grid, arm_id)
    phase3_dir <- app_joint_qvp_phase4h_phase3_dir(arm_run_manifest$phase3_out_dir[[ii]])
    row <- app_joint_qvp_phase4g_screen_metrics(phase3_dir, arm)
    row$arm_id <- arm_id
    row$arm_role <- arm$arm_role[[1L]]
    rows[[length(rows) + 1L]] <- row
  }
  out <- app_bind_rows_fill(rows)
  first <- c("arm_id", "arm_role")
  out[, unique(c(first, setdiff(names(out), first))), drop = FALSE]
}

app_joint_qvp_phase4i_aggregate_family <- function(crossing_by_scenario) {
  if (!nrow(crossing_by_scenario)) return(data.frame())
  keys <- unique(crossing_by_scenario[, c("screen_id", "screen_class", "tau0", "distribution_family"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  for (ii in seq_len(nrow(keys))) {
    idx <- crossing_by_scenario$screen_id == keys$screen_id[[ii]] &
      crossing_by_scenario$distribution_family == keys$distribution_family[[ii]]
    g <- crossing_by_scenario[idx, , drop = FALSE]
    rows[[ii]] <- data.frame(
      keys[ii, , drop = FALSE],
      n_scenarios = length(unique(g$scenario_id)),
      raw_crossing_pairs = sum(g$raw_crossing_pairs, na.rm = TRUE),
      raw_crossing_origins = sum(g$raw_crossing_origins, na.rm = TRUE),
      raw_max_crossing_magnitude = if (nrow(g)) max(g$raw_max_crossing_magnitude, na.rm = TRUE) else 0,
      contract_crossing_pairs = sum(g$contract_crossing_pairs, na.rm = TRUE),
      monotone_adjusted_origins = sum(g$monotone_adjusted_origins, na.rm = TRUE),
      max_monotone_adjustment = if (nrow(g)) max(g$max_monotone_adjustment, na.rm = TRUE) else 0,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_phase4i_tail_tradeoff <- function(candidate_ranking, crossing_by_tau_pair, truth_by_tau) {
  if (!nrow(candidate_ranking)) return(data.frame())
  rows <- lapply(seq_len(nrow(candidate_ranking)), function(ii) {
    arm_id <- candidate_ranking$screen_id[[ii]]
    lower <- crossing_by_tau_pair[crossing_by_tau_pair$screen_id == arm_id &
      abs(crossing_by_tau_pair$lower_tau - 0.05) < 1.0e-10 &
      abs(crossing_by_tau_pair$upper_tau - 0.10) < 1.0e-10, , drop = FALSE]
    upper <- crossing_by_tau_pair[crossing_by_tau_pair$screen_id == arm_id &
      abs(crossing_by_tau_pair$lower_tau - 0.90) < 1.0e-10 &
      abs(crossing_by_tau_pair$upper_tau - 0.95) < 1.0e-10, , drop = FALSE]
    tail95 <- truth_by_tau[truth_by_tau$screen_id == arm_id & abs(truth_by_tau$tau - 0.95) < 1.0e-10, , drop = FALSE]
    data.frame(
      arm_id = arm_id,
      tau0 = candidate_ranking$tau0[[ii]],
      raw_crossing_pairs = candidate_ranking$raw_crossing_pairs[[ii]],
      lower_tail_005_010_raw_crossing_pairs = if (nrow(lower)) lower$raw_crossing_pairs[[1L]] else NA_real_,
      upper_tail_090_095_raw_crossing_pairs = if (nrow(upper)) upper$raw_crossing_pairs[[1L]] else NA_real_,
      truth_mae_mean = candidate_ranking$truth_mae_mean[[ii]],
      truth_mae_tau095 = if (nrow(tail95)) tail95$mae_to_truth_mean[[1L]] else NA_real_,
      vb_max_iter_rate = candidate_ranking$vb_max_iter_rate[[ii]],
      runtime_total_sec = candidate_ranking$runtime_total_sec[[ii]],
      rank = candidate_ranking$rank[[ii]],
      screen_status = candidate_ranking$screen_status[[ii]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_phase4i_candidate_recommendation <- function(
  candidate_ranking,
  crossing_by_tau_pair,
  primary_arm_id = "tau0_0p10_primary"
) {
  failing_contract <- candidate_ranking[candidate_ranking$contract_crossing_pairs > 0, , drop = FALSE]
  primary <- candidate_ranking[candidate_ranking$arm_id == primary_arm_id | candidate_ranking$screen_id == primary_arm_id, , drop = FALSE]
  if (!nrow(primary)) primary <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE][1L, , drop = FALSE]
  ordered <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE]
  best <- ordered[1L, , drop = FALSE]
  upper <- crossing_by_tau_pair[abs(crossing_by_tau_pair$lower_tau - 0.90) < 1.0e-10 &
    abs(crossing_by_tau_pair$upper_tau - 0.95) < 1.0e-10, , drop = FALSE]
  best_upper <- upper$raw_crossing_pairs[upper$screen_id == best$screen_id[[1L]]]
  primary_upper <- upper$raw_crossing_pairs[upper$screen_id == primary$screen_id[[1L]]]
  best_upper <- if (length(best_upper)) best_upper[[1L]] else NA_real_
  primary_upper <- if (length(primary_upper)) primary_upper[[1L]] else NA_real_
  finite_core <- all(is.finite(best$raw_crossing_pairs), is.finite(best$truth_mae_mean), is.finite(best$vb_max_iter_rate))
  truth_competitive <- is.finite(best$truth_mae_mean[[1L]]) &&
    is.finite(primary$truth_mae_mean[[1L]]) &&
    best$truth_mae_mean[[1L]] <= 1.01 * primary$truth_mae_mean[[1L]]
  upper_ok <- !is.finite(best_upper) || !is.finite(primary_upper) || best_upper <= primary_upper
  vb_ok <- !is.finite(best$vb_max_iter_rate[[1L]]) || best$vb_max_iter_rate[[1L]] <= 0.20
  status <- if (nrow(failing_contract)) {
    "blocked_contract_crossing"
  } else if (!finite_core) {
    "review_nonfinite_candidate_metric"
  } else if (best$screen_id[[1L]] == primary$screen_id[[1L]] && truth_competitive && upper_ok) {
    "primary_candidate_for_calibration_or_article_candidate_followup"
  } else if (truth_competitive && upper_ok && vb_ok) {
    "comparator_candidate_for_calibration_followup"
  } else {
    "review_no_candidate_ready"
  }
  data.frame(
    scope = "phase4i_tau0_candidate_calibration_pilot",
    gate_status = if (nrow(failing_contract)) "fail" else "review",
    recommendation_status = status,
    primary_arm_id = primary$screen_id[[1L]],
    best_arm_id = best$screen_id[[1L]],
    best_raw_crossing_pairs = best$raw_crossing_pairs[[1L]],
    primary_raw_crossing_pairs = primary$raw_crossing_pairs[[1L]],
    best_upper_tail_crossing_pairs = best_upper,
    primary_upper_tail_crossing_pairs = primary_upper,
    best_contract_crossing_pairs = best$contract_crossing_pairs[[1L]],
    best_truth_mae_mean = best$truth_mae_mean[[1L]],
    primary_truth_mae_mean = primary$truth_mae_mean[[1L]],
    best_vb_max_iter_rate = best$vb_max_iter_rate[[1L]],
    best_runtime_ratio = best$runtime_ratio[[1L]],
    note = app_joint_qvp_ts_assessment_note(c(
      if (nrow(failing_contract)) "contract crossings block Phase 4i promotion",
      if (!nrow(failing_contract)) "contract crossings remain zero under the raw/contract policy",
      if (best$screen_id[[1L]] == primary$screen_id[[1L]]) "primary tau0 0.10 remains the best ranked candidate",
      if (best$screen_id[[1L]] != primary$screen_id[[1L]]) "a comparator arm ranked ahead of the primary arm",
      if (!truth_competitive) "truth MAE review relative to primary",
      if (!upper_ok) "upper-tail 0.90-0.95 raw crossing review",
      if (!vb_ok) "VB max-iteration rate review",
      "Phase 4i is calibration-pilot evidence and does not freeze article claims"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4i_assessment <- function(
  candidate_registry,
  fixture_manifest,
  arm_run_manifest,
  candidate_metric_summary,
  candidate_ranking,
  candidate_recommendation
) {
  registry_ok <- tryCatch({
    app_joint_qvp_validate_synthetic_dgp_registry(candidate_registry)
    TRUE
  }, error = function(e) FALSE)
  fixture_ok <- nrow(fixture_manifest) > 0L && all(fixture_manifest$hash_verified)
  nested_ok <- nrow(arm_run_manifest) > 0L && all(app_as_bool_vec(arm_run_manifest$manifest_hashes_verified))
  finite_ok <- nrow(candidate_metric_summary) > 0L &&
    all(is.finite(candidate_metric_summary$truth_mae_mean)) &&
    all(is.finite(candidate_metric_summary$raw_crossing_pairs)) &&
    all(is.finite(candidate_metric_summary$contract_crossing_pairs))
  contract_crossing_total <- if (nrow(candidate_metric_summary)) sum(candidate_metric_summary$contract_crossing_pairs, na.rm = TRUE) else NA_real_
  raw_crossing_total <- if (nrow(candidate_metric_summary)) sum(candidate_metric_summary$raw_crossing_pairs, na.rm = TRUE) else NA_real_
  vb_max_iter_rate <- if (nrow(candidate_metric_summary)) mean(candidate_metric_summary$vb_max_iter_rate, na.rm = TRUE) else NA_real_
  contract_ok <- is.finite(contract_crossing_total) && contract_crossing_total == 0
  ranking_ok <- nrow(candidate_ranking) > 0L && all(is.finite(candidate_ranking$ranking_score))
  hard_fail <- !registry_ok || !fixture_ok || !nested_ok || !finite_ok || !contract_ok || !ranking_ok
  raw_review <- is.finite(raw_crossing_total) && raw_crossing_total > 0
  vb_review <- is.finite(vb_max_iter_rate) && vb_max_iter_rate > 0.20
  recommendation_review <- !candidate_recommendation$recommendation_status[[1L]] %in% c(
    "primary_candidate_for_calibration_or_article_candidate_followup",
    "comparator_candidate_for_calibration_followup"
  )
  data.frame(
    scope = "phase4i_tau0_candidate_calibration_pilot",
    implementation_status = if (hard_fail) "fail" else "pass",
    fixture_status = if (fixture_ok) "pass" else "fail",
    nested_manifest_status = if (nested_ok) "pass" else "fail",
    contract_crossing_status = if (contract_ok) "pass" else "fail",
    raw_crossing_status = if (raw_review) "review" else "pass",
    vb_convergence_status = if (vb_review) "review" else "pass",
    recommendation_status = candidate_recommendation$recommendation_status[[1L]],
    gate_status = if (hard_fail) "fail" else if (raw_review || vb_review || recommendation_review) "review" else "pass",
    n_registry_rows = nrow(candidate_registry),
    n_arms = nrow(candidate_metric_summary),
    fixture_manifest_hashes_verified = fixture_ok,
    all_phase3_manifest_hashes_verified = nested_ok,
    total_raw_crossing_pairs = raw_crossing_total,
    total_contract_crossing_pairs = contract_crossing_total,
    mean_vb_max_iter_rate = vb_max_iter_rate,
    note = app_joint_qvp_ts_assessment_note(c(
      if (!registry_ok) "malformed candidate calibration registry",
      if (!fixture_ok) "fixture hashes missing or unverifiable",
      if (!nested_ok) "nested Phase 3 hashes missing or unverifiable",
      if (!finite_ok) "nonfinite candidate metrics",
      if (!contract_ok) "contract forecast crossings",
      if (!ranking_ok) "nonfinite ranking scores",
      if (raw_review) "raw crossings remain diagnostic review evidence",
      if (vb_review) "VB max-iteration rate review",
      if (recommendation_review) "candidate recommendation remains review-level"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4i_readme_lines <- function(run_config, assessment, recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Phase 4i Tau0 Candidate Calibration Pilot",
    "",
    "This artifact directory runs a replicated calibration-pilot comparison of the Phase 4h tau0 candidates.",
    "It materializes one shared Phase 1 fixture directory, runs Phase 3 forecast validation once per tau0 arm, and keeps the raw/contract forecast policy intact.",
    "",
    sprintf("- Tier: %s", run_config$tier[[1L]]),
    sprintf("- Candidate registry rows: %s", run_config$n_candidate_registry_rows[[1L]]),
    sprintf("- Candidate arms: %s", run_config$n_candidate_arms[[1L]]),
    sprintf("- Gate: %s", assessment$gate_status[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    "",
    "Primary files:",
    "",
    "- `candidate_arm_grid.csv`: tau0 arms and fixed prior/design controls.",
    "- `candidate_calibration_registry.csv`: replicated calibration-pilot registry with preserved seed roles.",
    "- `candidate_run_config.csv`: size, seed, VB, refit, and fixture controls.",
    "- `candidate_arm_run_manifest.csv`: nested Phase 3 artifact manifest verification by arm.",
    "- `candidate_metric_summary.csv`: raw/contract crossings, truth scores, hit errors, convergence, and runtime by arm.",
    "- `candidate_ranking.csv`: conservative ranking relative to tau0 0.10 primary.",
    "- `candidate_crossing_by_*`: raw and contract crossing diagnostics by arm, scenario, family, and adjacent tau pair.",
    "- `candidate_truth_by_tau.csv`: tau-specific truth-distance diagnostics.",
    "- `candidate_tail_tradeoff_summary.csv`: compact lower/upper tail crossing and tau 0.95 truth tradeoff table.",
    "- `candidate_recommendation.csv`: conservative readiness recommendation.",
    "- `phase4i_readiness_assessment.csv`: pass/review/fail implementation and calibration-pilot gates.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 4i root artifacts.",
    "",
    "Interpretation:",
    "",
    "Phase 4i can identify a candidate tau0 setting for the next calibration/article-candidate workflow. It does not freeze final article evidence."
  )
}

app_joint_qvp_run_synthetic_dgp_phase4i_tau0_candidate_calibration_pilot <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_phase4i_candidate_dir(),
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL,
  scenario_ids = NULL,
  tier = c("smoke", "calibration_pilot"),
  tau0_arms = c(0.10, 0.15),
  include_reference_arm = FALSE,
  arm_ids = NULL,
  n_replicates = NULL,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL,
  vb_max_iter = NULL,
  adaptive_vb_max_iter_grid = NULL,
  refit_stride = NULL,
  forecast_origin_stride = NULL,
  max_origins_per_scenario = NULL,
  vb_tol = 1.0e-4,
  kappa = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  primary_arm_id = "tau0_0p10_primary"
) {
  tier <- match.arg(as.character(tier)[[1L]], c("smoke", "calibration_pilot"))
  if (!is.null(scenario_ids)) {
    scenario_ids <- unique(as.character(scenario_ids))
    scenario_ids <- scenario_ids[nzchar(scenario_ids)]
    if (!length(scenario_ids)) scenario_ids <- NULL
  }
  if (!is.null(arm_ids)) {
    arm_ids <- unique(as.character(arm_ids))
    arm_ids <- arm_ids[nzchar(arm_ids)]
    if (!length(arm_ids)) arm_ids <- NULL
  }
  defaults <- app_joint_qvp_phase4i_tier_defaults(tier)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  n_replicates <- as.integer(n_replicates %||% defaults$n_replicates)
  seed_base <- as.integer(seed_base %||% defaults$seed_base)
  simulated_length <- as.integer(simulated_length %||% defaults$simulated_length)
  washout_length <- as.integer(washout_length %||% defaults$washout_length)
  train_length <- as.integer(train_length %||% defaults$train_length)
  test_length <- as.integer(test_length %||% defaults$test_length)
  vb_max_iter <- as.integer(vb_max_iter %||% defaults$vb_max_iter)
  adaptive_vb_max_iter_grid <- app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid %||% defaults$adaptive_vb_max_iter_grid)
  refit_stride <- as.integer(refit_stride %||% defaults$refit_stride)
  forecast_origin_stride <- as.integer(forecast_origin_stride %||% defaults$forecast_origin_stride)
  max_origins_per_scenario <- max_origins_per_scenario %||% defaults$max_origins_per_scenario
  base_registry <- if (is.null(registry)) app_joint_qvp_load_synthetic_dgp_registry(registry_path) else registry
  candidate_registry <- app_joint_qvp_phase4i_build_candidate_registry(
    registry_path = registry_path,
    registry = base_registry,
    scenario_ids = scenario_ids,
    tier = tier,
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length
  )
  arm_grid <- app_joint_qvp_phase4i_tau0_arm_grid(tau0_arms = tau0_arms, include_reference_arm = include_reference_arm, arm_ids = arm_ids)
  if (!primary_arm_id %in% arm_grid$arm_id) primary_arm_id <- arm_grid$arm_id[[1L]]

  fixture_dir <- file.path(out_dir, "phase1_fixtures_candidate")
  app_joint_qvp_materialize_synthetic_dgp_registry(out_dir = fixture_dir, registry = candidate_registry)
  fixture_manifest <- app_joint_qvp_phase4_manifest_with_hashes(fixture_dir)
  if (!all(fixture_manifest$hash_verified)) stop("Phase 4i fixture manifest failed hash verification.", call. = FALSE)

  manifest_rows <- list()
  for (ii in seq_len(nrow(arm_grid))) {
    arm <- arm_grid[ii, , drop = FALSE]
    phase3_dir <- file.path(out_dir, "arm_runs", arm$arm_id[[1L]])
    phase3_result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
      out_dir = phase3_dir,
      fixture_dir = fixture_dir,
      scenario_ids = candidate_registry$scenario_id,
      kappa = kappa,
      tau0 = arm$tau0[[1L]],
      zeta2 = arm$zeta2[[1L]],
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = arm$alpha_prior_sd[[1L]],
      alpha_min_spacing = arm$alpha_min_spacing[[1L]],
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      rhs_vb_inner = as.integer(arm$rhs_vb_inner[[1L]]),
      refit_stride = refit_stride,
      forecast_origin_stride = forecast_origin_stride,
      max_origins_per_scenario = max_origins_per_scenario,
      vb_tol = vb_tol
    )
    phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_result$out_dir)
    manifest_rows[[length(manifest_rows) + 1L]] <- data.frame(
      arm_id = arm$arm_id[[1L]],
      screen_id = arm$screen_id[[1L]],
      arm_role = arm$arm_role[[1L]],
      phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
      phase3_artifact_manifest = app_prefer_repo_relative_path(phase3_result$paths[["artifact_manifest"]]),
      n_manifest_rows = nrow(phase3_manifest),
      manifest_hashes_verified = all(phase3_manifest$hash_verified),
      manifest_sha256 = app_sha256_file(phase3_result$paths[["artifact_manifest"]]),
      stringsAsFactors = FALSE
    )
  }
  arm_run_manifest <- do.call(rbind, manifest_rows)
  candidate_metric_summary <- app_joint_qvp_phase4i_metric_summary(arm_run_manifest, arm_grid)
  candidate_ranking <- app_joint_qvp_phase4g_compare_to_baseline(candidate_metric_summary, baseline_screen_id = primary_arm_id)
  if (!"arm_id" %in% names(candidate_ranking)) candidate_ranking$arm_id <- candidate_ranking$screen_id
  if (!"arm_role" %in% names(candidate_ranking)) candidate_ranking$arm_role <- arm_grid$arm_role[match(candidate_ranking$screen_id, arm_grid$screen_id)]
  candidate_ranking <- candidate_ranking[, unique(c("arm_id", "arm_role", setdiff(names(candidate_ranking), c("arm_id", "arm_role")))), drop = FALSE]
  candidate_crossing_by_arm <- candidate_ranking[, c(
    "arm_id", "arm_role", "screen_class", "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner",
    "raw_crossing_pairs", "raw_crossing_origins", "raw_max_crossing_magnitude",
    "contract_crossing_pairs", "contract_max_crossing_magnitude",
    "monotone_adjusted_origins", "max_monotone_adjustment", "screen_status", "note"
  ), drop = FALSE]
  candidate_crossing_by_scenario <- app_joint_qvp_phase4h_crossing_by_scenario(arm_run_manifest, arm_grid, candidate_registry)
  candidate_crossing_by_family <- app_joint_qvp_phase4i_aggregate_family(candidate_crossing_by_scenario)
  candidate_crossing_by_tau_pair <- app_joint_qvp_phase4h_crossing_by_tau_pair(arm_run_manifest, arm_grid)
  candidate_truth_by_tau <- app_joint_qvp_phase4h_truth_by_tau(arm_run_manifest, arm_grid)
  candidate_tail_tradeoff_summary <- app_joint_qvp_phase4i_tail_tradeoff(candidate_ranking, candidate_crossing_by_tau_pair, candidate_truth_by_tau)
  candidate_vb_runtime_summary <- candidate_ranking[, c(
    "arm_id", "arm_role", "screen_class", "tau0", "vb_refit_count", "vb_max_iter_count",
    "vb_max_iter_rate", "vb_max_iter_rate_delta", "runtime_total_sec",
    "runtime_refit_sec", "runtime_ratio", "screen_status"
  ), drop = FALSE]
  candidate_recommendation <- app_joint_qvp_phase4i_candidate_recommendation(candidate_ranking, candidate_crossing_by_tau_pair, primary_arm_id = primary_arm_id)
  phase4i_readiness_assessment <- app_joint_qvp_phase4i_assessment(
    candidate_registry = candidate_registry,
    fixture_manifest = fixture_manifest,
    arm_run_manifest = arm_run_manifest,
    candidate_metric_summary = candidate_metric_summary,
    candidate_ranking = candidate_ranking,
    candidate_recommendation = candidate_recommendation
  )
  candidate_run_config <- data.frame(
    phase = "phase4i_tau0_candidate_calibration_pilot",
    tier = tier,
    registry_path = if (is.null(registry_path)) NA_character_ else app_prefer_repo_relative_path(registry_path),
    registry_sha256 = if (!is.null(registry_path) && file.exists(registry_path)) app_sha256_file(registry_path) else NA_character_,
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    fixture_manifest_sha256 = app_sha256_file(file.path(fixture_dir, "artifact_manifest.csv")),
    n_candidate_registry_rows = nrow(candidate_registry),
    n_base_scenarios = length(unique(candidate_registry$base_scenario_id)),
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length,
    n_candidate_arms = nrow(arm_grid),
    primary_arm_id = primary_arm_id,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(adaptive_vb_max_iter_grid, collapse = ","),
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = if (is.finite(as.numeric(max_origins_per_scenario))) as.integer(max_origins_per_scenario) else NA_integer_,
    vb_tol = vb_tol,
    kappa = kappa,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    all_fixture_hashes_verified = all(fixture_manifest$hash_verified),
    all_phase3_manifest_hashes_verified = all(app_as_bool_vec(arm_run_manifest$manifest_hashes_verified)),
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase4i_readme_lines(candidate_run_config, phase4i_readiness_assessment, candidate_recommendation), readme_path, useBytes = TRUE)
  paths <- c(
    candidate_arm_grid = app_joint_qvp_write_csv(arm_grid, file.path(out_dir, "candidate_arm_grid.csv")),
    candidate_calibration_registry = app_joint_qvp_write_csv(candidate_registry, file.path(out_dir, "candidate_calibration_registry.csv")),
    candidate_run_config = app_joint_qvp_write_csv(candidate_run_config, file.path(out_dir, "candidate_run_config.csv")),
    candidate_arm_run_manifest = app_joint_qvp_write_csv(arm_run_manifest, file.path(out_dir, "candidate_arm_run_manifest.csv")),
    candidate_metric_summary = app_joint_qvp_write_csv(candidate_metric_summary, file.path(out_dir, "candidate_metric_summary.csv")),
    candidate_ranking = app_joint_qvp_write_csv(candidate_ranking, file.path(out_dir, "candidate_ranking.csv")),
    candidate_crossing_by_arm = app_joint_qvp_write_csv(candidate_crossing_by_arm, file.path(out_dir, "candidate_crossing_by_arm.csv")),
    candidate_crossing_by_scenario = app_joint_qvp_write_csv(candidate_crossing_by_scenario, file.path(out_dir, "candidate_crossing_by_scenario.csv")),
    candidate_crossing_by_family = app_joint_qvp_write_csv(candidate_crossing_by_family, file.path(out_dir, "candidate_crossing_by_family.csv")),
    candidate_crossing_by_tau_pair = app_joint_qvp_write_csv(candidate_crossing_by_tau_pair, file.path(out_dir, "candidate_crossing_by_tau_pair.csv")),
    candidate_truth_by_tau = app_joint_qvp_write_csv(candidate_truth_by_tau, file.path(out_dir, "candidate_truth_by_tau.csv")),
    candidate_tail_tradeoff_summary = app_joint_qvp_write_csv(candidate_tail_tradeoff_summary, file.path(out_dir, "candidate_tail_tradeoff_summary.csv")),
    candidate_vb_runtime_summary = app_joint_qvp_write_csv(candidate_vb_runtime_summary, file.path(out_dir, "candidate_vb_runtime_summary.csv")),
    candidate_recommendation = app_joint_qvp_write_csv(candidate_recommendation, file.path(out_dir, "candidate_recommendation.csv")),
    phase4i_readiness_assessment = app_joint_qvp_write_csv(phase4i_readiness_assessment, file.path(out_dir, "phase4i_readiness_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    fixture_dir = fixture_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    candidate_arm_grid = arm_grid,
    candidate_calibration_registry = candidate_registry,
    candidate_run_config = candidate_run_config,
    candidate_arm_run_manifest = arm_run_manifest,
    candidate_metric_summary = candidate_metric_summary,
    candidate_ranking = candidate_ranking,
    candidate_crossing_by_arm = candidate_crossing_by_arm,
    candidate_crossing_by_scenario = candidate_crossing_by_scenario,
    candidate_crossing_by_family = candidate_crossing_by_family,
    candidate_crossing_by_tau_pair = candidate_crossing_by_tau_pair,
    candidate_truth_by_tau = candidate_truth_by_tau,
    candidate_tail_tradeoff_summary = candidate_tail_tradeoff_summary,
    candidate_vb_runtime_summary = candidate_vb_runtime_summary,
    candidate_recommendation = candidate_recommendation,
    phase4i_readiness_assessment = phase4i_readiness_assessment
  )
}

app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704")
}

app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir <- function() {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_article_candidate_freeze_20260704")
}

app_joint_qvp_phase4j_tier_defaults <- function(tier = "tau0_candidate_launch") {
  tier <- as.character(tier)[[1L]]
  if (!identical(tier, "tau0_candidate_launch")) {
    stop("Phase 4j supports only tier='tau0_candidate_launch'.", call. = FALSE)
  }
  list(
    simulated_length = 2500L,
    washout_length = 500L,
    train_length = 1000L,
    test_length = 1000L,
    n_replicates = 10L,
    seed_base = 202607400L,
    vb_max_iter = 720L,
    adaptive_vb_max_iter_grid = c(720L, 960L),
    refit_stride = 30L,
    forecast_origin_stride = 10L,
    max_origins_per_scenario = 100L
  )
}

app_joint_qvp_phase4j_tau0_arm_grid <- function(
  tau0_arms = c(0.10, 0.15),
  include_reference_arm = FALSE,
  arm_ids = NULL
) {
  arm <- app_joint_qvp_phase4i_tau0_arm_grid(
    tau0_arms = tau0_arms,
    include_reference_arm = include_reference_arm,
    arm_ids = arm_ids
  )
  arm$screen_class <- "tau0_candidate_launch"
  arm$rationale <- ifelse(
    arm$arm_id == "tau0_0p10_primary",
    "Phase 4j primary launch candidate selected from Phase 4h evidence.",
    ifelse(
      arm$arm_id == "tau0_0p15_comparator",
      "Phase 4j comparator launch candidate for upper-tail and runtime tradeoff assessment.",
      "Phase 4j optional reference arm retained only when explicitly requested."
    )
  )
  rownames(arm) <- NULL
  app_joint_qvp_validate_phase4_screen_grid(arm, "Phase 4j tau0 candidate launch arm grid")
}

app_joint_qvp_phase4j_build_launch_registry <- function(
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL,
  scenario_ids = NULL,
  n_replicates = NULL,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL
) {
  defaults <- app_joint_qvp_phase4j_tier_defaults()
  out <- app_joint_qvp_phase4_build_calibration_registry(
    registry_path = registry_path,
    registry = registry,
    scenario_ids = scenario_ids,
    tier = "article_candidate",
    n_replicates = as.integer(n_replicates %||% defaults$n_replicates),
    seed_base = as.integer(seed_base %||% defaults$seed_base),
    simulated_length = as.integer(simulated_length %||% defaults$simulated_length),
    washout_length = as.integer(washout_length %||% defaults$washout_length),
    train_length = as.integer(train_length %||% defaults$train_length),
    test_length = as.integer(test_length %||% defaults$test_length)
  )
  out$registry_version <- "phase4j_tau0_candidate_launch_20260704"
  out$scenario_id <- sub("__article_candidate_r", "__tau0_candidate_launch_r", out$scenario_id, fixed = TRUE)
  out$validation_tier <- "tau0_candidate_launch"
  out$seed_role <- "tau0_candidate_launch_replicate_seed"
  out$notes <- sub(" Phase 4 article_candidate replicate ", " Phase 4j tau0 candidate launch replicate ", out$notes, fixed = TRUE)
  rownames(out) <- NULL
  app_joint_qvp_validate_synthetic_dgp_registry(out)
  out
}

app_joint_qvp_phase4j_contains_nonlaunch_label <- function(...) {
  vals <- unlist(list(...), use.names = FALSE)
  vals <- vals[!is.na(vals)]
  any(grepl("smoke|pilot|calibration_pilot", as.character(vals), ignore.case = TRUE))
}

app_joint_qvp_phase4j_recommendation <- function(
  candidate_ranking,
  crossing_by_tau_pair,
  primary_arm_id = "tau0_0p10_primary"
) {
  failing_contract <- candidate_ranking[candidate_ranking$contract_crossing_pairs > 0, , drop = FALSE]
  primary <- candidate_ranking[candidate_ranking$arm_id == primary_arm_id | candidate_ranking$screen_id == primary_arm_id, , drop = FALSE]
  if (!nrow(primary)) primary <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE][1L, , drop = FALSE]
  ordered <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE]
  best <- ordered[1L, , drop = FALSE]
  comparator <- candidate_ranking[candidate_ranking$arm_id == "tau0_0p15_comparator" | candidate_ranking$screen_id == "tau0_0p15_comparator", , drop = FALSE]
  upper <- crossing_by_tau_pair[
    abs(crossing_by_tau_pair$lower_tau - 0.90) < 1.0e-10 &
      abs(crossing_by_tau_pair$upper_tau - 0.95) < 1.0e-10,
    , drop = FALSE
  ]
  upper_count <- function(id) {
    vals <- upper$raw_crossing_pairs[upper$screen_id == id]
    if (length(vals)) vals[[1L]] else NA_real_
  }
  primary_upper <- upper_count(primary$screen_id[[1L]])
  best_upper <- upper_count(best$screen_id[[1L]])
  comparator_upper <- if (nrow(comparator)) upper_count(comparator$screen_id[[1L]]) else NA_real_
  comparator_eligible <- nrow(comparator) > 0L &&
    comparator$contract_crossing_pairs[[1L]] == 0 &&
    is.finite(comparator$truth_mae_mean[[1L]]) &&
    is.finite(primary$truth_mae_mean[[1L]]) &&
    comparator$truth_mae_mean[[1L]] <= 1.02 * primary$truth_mae_mean[[1L]] &&
    (!is.finite(comparator_upper) || !is.finite(primary_upper) || comparator_upper <= primary_upper) &&
    (comparator$raw_crossing_pairs[[1L]] < primary$raw_crossing_pairs[[1L]] ||
      comparator$runtime_total_sec[[1L]] < 0.90 * primary$runtime_total_sec[[1L]])
  selected <- if (nrow(failing_contract)) {
    primary[0L, , drop = FALSE]
  } else if (comparator_eligible) {
    comparator
  } else {
    primary
  }
  recommendation_status <- if (nrow(failing_contract)) {
    "blocked_contract_crossing"
  } else if (!nrow(selected)) {
    "review_no_tau0_freeze"
  } else if (selected$screen_id[[1L]] == primary$screen_id[[1L]]) {
    "primary_selected_for_article_candidate_freeze"
  } else {
    "comparator_selected_for_article_candidate_freeze"
  }
  data.frame(
    scope = "phase4j_tau0_candidate_launch",
    gate_status = if (nrow(failing_contract)) "fail" else "review",
    recommendation_status = recommendation_status,
    selected_arm_id = if (nrow(selected)) selected$screen_id[[1L]] else NA_character_,
    selected_tau0 = if (nrow(selected)) selected$tau0[[1L]] else NA_real_,
    primary_arm_id = primary$screen_id[[1L]],
    best_ranked_arm_id = best$screen_id[[1L]],
    best_raw_crossing_pairs = best$raw_crossing_pairs[[1L]],
    primary_raw_crossing_pairs = primary$raw_crossing_pairs[[1L]],
    comparator_raw_crossing_pairs = if (nrow(comparator)) comparator$raw_crossing_pairs[[1L]] else NA_real_,
    best_upper_tail_crossing_pairs = best_upper,
    primary_upper_tail_crossing_pairs = primary_upper,
    comparator_upper_tail_crossing_pairs = comparator_upper,
    selected_contract_crossing_pairs = if (nrow(selected)) selected$contract_crossing_pairs[[1L]] else NA_real_,
    selected_truth_mae_mean = if (nrow(selected)) selected$truth_mae_mean[[1L]] else NA_real_,
    primary_truth_mae_mean = primary$truth_mae_mean[[1L]],
    comparator_truth_mae_mean = if (nrow(comparator)) comparator$truth_mae_mean[[1L]] else NA_real_,
    selected_vb_max_iter_rate = if (nrow(selected)) selected$vb_max_iter_rate[[1L]] else NA_real_,
    selected_runtime_total_sec = if (nrow(selected)) selected$runtime_total_sec[[1L]] else NA_real_,
    note = app_joint_qvp_ts_assessment_note(c(
      if (nrow(failing_contract)) "contract crossings block tau0 launch freeze",
      if (!nrow(failing_contract)) "contract crossings remain zero under the raw/contract policy",
      if (comparator_eligible) "tau0 0.15 meets conservative comparator promotion rule",
      if (!comparator_eligible && nrow(comparator)) "tau0 0.10 retained unless comparator improves broad evidence",
      "raw crossings remain diagnostic review evidence, not hidden failures"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4j_assessment <- function(
  launch_registry,
  fixture_manifest,
  arm_run_manifest,
  launch_metric_summary,
  launch_ranking,
  launch_recommendation,
  launch_run_config
) {
  registry_ok <- tryCatch({
    app_joint_qvp_validate_synthetic_dgp_registry(launch_registry)
    TRUE
  }, error = function(e) FALSE)
  fixture_ok <- nrow(fixture_manifest) > 0L && all(fixture_manifest$hash_verified)
  nested_ok <- nrow(arm_run_manifest) > 0L && all(app_as_bool_vec(arm_run_manifest$manifest_hashes_verified))
  finite_ok <- nrow(launch_metric_summary) > 0L &&
    all(is.finite(launch_metric_summary$truth_mae_mean)) &&
    all(is.finite(launch_metric_summary$raw_crossing_pairs)) &&
    all(is.finite(launch_metric_summary$contract_crossing_pairs))
  contract_crossing_total <- if (nrow(launch_metric_summary)) sum(launch_metric_summary$contract_crossing_pairs, na.rm = TRUE) else NA_real_
  raw_crossing_total <- if (nrow(launch_metric_summary)) sum(launch_metric_summary$raw_crossing_pairs, na.rm = TRUE) else NA_real_
  vb_max_iter_rate <- if (nrow(launch_metric_summary)) mean(launch_metric_summary$vb_max_iter_rate, na.rm = TRUE) else NA_real_
  contract_ok <- is.finite(contract_crossing_total) && contract_crossing_total == 0
  ranking_ok <- nrow(launch_ranking) > 0L && all(is.finite(launch_ranking$ranking_score))
  nonlaunch_label <- app_joint_qvp_phase4j_contains_nonlaunch_label(
    launch_registry$registry_version,
    launch_registry$scenario_id,
    launch_registry$validation_tier,
    launch_registry$seed_role,
    launch_run_config$phase,
    launch_run_config$tier,
    launch_recommendation$scope
  )
  hard_fail <- !registry_ok || !fixture_ok || !nested_ok || !finite_ok || !contract_ok || !ranking_ok || nonlaunch_label
  raw_review <- is.finite(raw_crossing_total) && raw_crossing_total > 0
  vb_review <- is.finite(vb_max_iter_rate) && vb_max_iter_rate > 0.20
  recommendation_review <- !launch_recommendation$recommendation_status[[1L]] %in% c(
    "primary_selected_for_article_candidate_freeze",
    "comparator_selected_for_article_candidate_freeze"
  )
  data.frame(
    scope = "phase4j_tau0_candidate_launch",
    implementation_status = if (hard_fail) "fail" else "pass",
    fixture_status = if (fixture_ok) "pass" else "fail",
    nested_manifest_status = if (nested_ok) "pass" else "fail",
    label_status = if (nonlaunch_label) "fail" else "pass",
    contract_crossing_status = if (contract_ok) "pass" else "fail",
    raw_crossing_status = if (raw_review) "review" else "pass",
    vb_convergence_status = if (vb_review) "review" else "pass",
    recommendation_status = launch_recommendation$recommendation_status[[1L]],
    gate_status = if (hard_fail) "fail" else if (raw_review || vb_review || recommendation_review) "review" else "pass",
    n_registry_rows = nrow(launch_registry),
    n_arms = nrow(launch_metric_summary),
    fixture_manifest_hashes_verified = fixture_ok,
    all_phase3_manifest_hashes_verified = nested_ok,
    no_nonlaunch_labels = !nonlaunch_label,
    total_raw_crossing_pairs = raw_crossing_total,
    total_contract_crossing_pairs = contract_crossing_total,
    mean_vb_max_iter_rate = vb_max_iter_rate,
    selected_arm_id = launch_recommendation$selected_arm_id[[1L]],
    selected_tau0 = launch_recommendation$selected_tau0[[1L]],
    note = app_joint_qvp_ts_assessment_note(c(
      if (!registry_ok) "malformed launch registry",
      if (!fixture_ok) "fixture hashes missing or unverifiable",
      if (!nested_ok) "nested Phase 3 hashes missing or unverifiable",
      if (!finite_ok) "nonfinite launch metrics",
      if (!contract_ok) "contract forecast crossings",
      if (!ranking_ok) "nonfinite ranking scores",
      if (nonlaunch_label) "launch artifacts contain smoke/pilot labels",
      if (raw_review) "raw crossings remain diagnostic review evidence",
      if (vb_review) "VB max-iteration rate review",
      if (recommendation_review) "tau0 freeze recommendation remains review-level"
    )),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4j_readme_lines <- function(run_config, assessment, recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Forecast Phase 4j Tau0 Candidate Launch",
    "",
    "This artifact directory contains the actual launch-labelled two-arm tau0 candidate validation run.",
    "It compares tau0 0.10 and tau0 0.15 on shared replicated Phase 1 fixtures and runs Phase 3 forecast validation once per arm.",
    "Raw forecast quantiles remain diagnostic; monotone contract forecast quantiles are used for scoring.",
    "",
    sprintf("- Tier: %s", run_config$tier[[1L]]),
    sprintf("- Launch registry rows: %s", run_config$n_launch_registry_rows[[1L]]),
    sprintf("- Candidate arms: %s", run_config$n_candidate_arms[[1L]]),
    sprintf("- Gate: %s", assessment$gate_status[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    sprintf("- Selected arm: %s", recommendation$selected_arm_id[[1L]]),
    "",
    "Primary files:",
    "",
    "- `launch_arm_grid.csv`: tau0 launch arms and fixed prior/design controls.",
    "- `launch_registry.csv`: replicated launch registry with launch seed roles.",
    "- `launch_run_config.csv`: size, seed, VB, refit, and fixture controls.",
    "- `launch_arm_run_manifest.csv`: nested Phase 3 artifact manifest verification by arm.",
    "- `launch_metric_summary.csv`: raw/contract crossings, truth scores, hit errors, convergence, and runtime by arm.",
    "- `launch_ranking.csv`: conservative ranking relative to tau0 0.10 primary.",
    "- `launch_crossing_by_*`: raw and contract crossing diagnostics by arm, scenario, family, and adjacent tau pair.",
    "- `launch_truth_by_tau.csv`: tau-specific truth-distance diagnostics.",
    "- `launch_tail_tradeoff_summary.csv`: compact lower/upper tail crossing and tau 0.95 truth tradeoff table.",
    "- `launch_recommendation.csv`: tau0 freeze recommendation.",
    "- `phase4j_readiness_assessment.csv`: pass/review/fail implementation and launch gates.",
    "- `artifact_manifest.csv`: SHA-256 hashes for Phase 4j root artifacts.",
    "",
    "Interpretation:",
    "",
    "Phase 4j is launch-labelled evidence. If implementation gates pass, the selected arm can be promoted into the article-candidate freeze without duplicate compute."
  )
}

app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir(),
  registry_path = app_joint_qvp_default_synthetic_dgp_registry_path(),
  registry = NULL,
  scenario_ids = NULL,
  tier = "tau0_candidate_launch",
  tau0_arms = c(0.10, 0.15),
  include_reference_arm = FALSE,
  arm_ids = NULL,
  n_replicates = NULL,
  seed_base = NULL,
  simulated_length = NULL,
  washout_length = NULL,
  train_length = NULL,
  test_length = NULL,
  vb_max_iter = NULL,
  adaptive_vb_max_iter_grid = NULL,
  refit_stride = NULL,
  forecast_origin_stride = NULL,
  max_origins_per_scenario = NULL,
  vb_tol = 1.0e-4,
  kappa = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  primary_arm_id = "tau0_0p10_primary"
) {
  tier <- as.character(tier)[[1L]]
  if (!identical(tier, "tau0_candidate_launch")) stop("Phase 4j requires tier='tau0_candidate_launch'.", call. = FALSE)
  if (!is.null(scenario_ids)) {
    scenario_ids <- unique(as.character(scenario_ids))
    scenario_ids <- scenario_ids[nzchar(scenario_ids)]
    if (!length(scenario_ids)) scenario_ids <- NULL
  }
  if (!is.null(arm_ids)) {
    arm_ids <- unique(as.character(arm_ids))
    arm_ids <- arm_ids[nzchar(arm_ids)]
    if (!length(arm_ids)) arm_ids <- NULL
  }
  defaults <- app_joint_qvp_phase4j_tier_defaults(tier)
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  n_replicates <- as.integer(n_replicates %||% defaults$n_replicates)
  seed_base <- as.integer(seed_base %||% defaults$seed_base)
  simulated_length <- as.integer(simulated_length %||% defaults$simulated_length)
  washout_length <- as.integer(washout_length %||% defaults$washout_length)
  train_length <- as.integer(train_length %||% defaults$train_length)
  test_length <- as.integer(test_length %||% defaults$test_length)
  vb_max_iter <- as.integer(vb_max_iter %||% defaults$vb_max_iter)
  adaptive_vb_max_iter_grid <- app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid %||% defaults$adaptive_vb_max_iter_grid)
  refit_stride <- as.integer(refit_stride %||% defaults$refit_stride)
  forecast_origin_stride <- as.integer(forecast_origin_stride %||% defaults$forecast_origin_stride)
  max_origins_per_scenario <- max_origins_per_scenario %||% defaults$max_origins_per_scenario
  base_registry <- if (is.null(registry)) app_joint_qvp_load_synthetic_dgp_registry(registry_path) else registry
  launch_registry <- app_joint_qvp_phase4j_build_launch_registry(
    registry_path = registry_path,
    registry = base_registry,
    scenario_ids = scenario_ids,
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length
  )
  arm_grid <- app_joint_qvp_phase4j_tau0_arm_grid(
    tau0_arms = tau0_arms,
    include_reference_arm = include_reference_arm,
    arm_ids = arm_ids
  )
  if (!primary_arm_id %in% arm_grid$arm_id) primary_arm_id <- arm_grid$arm_id[[1L]]

  fixture_dir <- file.path(out_dir, "phase1_fixtures_launch")
  app_joint_qvp_materialize_synthetic_dgp_registry(out_dir = fixture_dir, registry = launch_registry)
  fixture_manifest <- app_joint_qvp_phase4_manifest_with_hashes(fixture_dir)
  if (!all(fixture_manifest$hash_verified)) stop("Phase 4j fixture manifest failed hash verification.", call. = FALSE)

  manifest_rows <- list()
  for (ii in seq_len(nrow(arm_grid))) {
    arm <- arm_grid[ii, , drop = FALSE]
    phase3_dir <- file.path(out_dir, "arm_runs", arm$arm_id[[1L]])
    phase3_result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
      out_dir = phase3_dir,
      fixture_dir = fixture_dir,
      scenario_ids = launch_registry$scenario_id,
      kappa = kappa,
      tau0 = arm$tau0[[1L]],
      zeta2 = arm$zeta2[[1L]],
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = arm$alpha_prior_sd[[1L]],
      alpha_min_spacing = arm$alpha_min_spacing[[1L]],
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      rhs_vb_inner = as.integer(arm$rhs_vb_inner[[1L]]),
      refit_stride = refit_stride,
      forecast_origin_stride = forecast_origin_stride,
      max_origins_per_scenario = max_origins_per_scenario,
      vb_tol = vb_tol
    )
    phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_result$out_dir)
    manifest_rows[[length(manifest_rows) + 1L]] <- data.frame(
      arm_id = arm$arm_id[[1L]],
      screen_id = arm$screen_id[[1L]],
      arm_role = arm$arm_role[[1L]],
      phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
      phase3_artifact_manifest = app_prefer_repo_relative_path(phase3_result$paths[["artifact_manifest"]]),
      n_manifest_rows = nrow(phase3_manifest),
      manifest_hashes_verified = all(phase3_manifest$hash_verified),
      manifest_sha256 = app_sha256_file(phase3_result$paths[["artifact_manifest"]]),
      stringsAsFactors = FALSE
    )
  }
  arm_run_manifest <- do.call(rbind, manifest_rows)
  launch_metric_summary <- app_joint_qvp_phase4i_metric_summary(arm_run_manifest, arm_grid)
  launch_ranking <- app_joint_qvp_phase4g_compare_to_baseline(launch_metric_summary, baseline_screen_id = primary_arm_id)
  if (!"arm_id" %in% names(launch_ranking)) launch_ranking$arm_id <- launch_ranking$screen_id
  if (!"arm_role" %in% names(launch_ranking)) launch_ranking$arm_role <- arm_grid$arm_role[match(launch_ranking$screen_id, arm_grid$screen_id)]
  launch_ranking <- launch_ranking[, unique(c("arm_id", "arm_role", setdiff(names(launch_ranking), c("arm_id", "arm_role")))), drop = FALSE]
  launch_crossing_by_arm <- launch_ranking[, c(
    "arm_id", "arm_role", "screen_class", "tau0", "zeta2", "alpha_prior_sd", "rhs_vb_inner",
    "raw_crossing_pairs", "raw_crossing_origins", "raw_max_crossing_magnitude",
    "contract_crossing_pairs", "contract_max_crossing_magnitude",
    "monotone_adjusted_origins", "max_monotone_adjustment", "screen_status", "note"
  ), drop = FALSE]
  launch_crossing_by_scenario <- app_joint_qvp_phase4h_crossing_by_scenario(arm_run_manifest, arm_grid, launch_registry)
  launch_crossing_by_family <- app_joint_qvp_phase4i_aggregate_family(launch_crossing_by_scenario)
  launch_crossing_by_tau_pair <- app_joint_qvp_phase4h_crossing_by_tau_pair(arm_run_manifest, arm_grid)
  launch_truth_by_tau <- app_joint_qvp_phase4h_truth_by_tau(arm_run_manifest, arm_grid)
  launch_tail_tradeoff_summary <- app_joint_qvp_phase4i_tail_tradeoff(launch_ranking, launch_crossing_by_tau_pair, launch_truth_by_tau)
  launch_vb_runtime_summary <- launch_ranking[, c(
    "arm_id", "arm_role", "screen_class", "tau0", "vb_refit_count", "vb_max_iter_count",
    "vb_max_iter_rate", "vb_max_iter_rate_delta", "runtime_total_sec",
    "runtime_refit_sec", "runtime_ratio", "screen_status"
  ), drop = FALSE]
  launch_recommendation <- app_joint_qvp_phase4j_recommendation(
    launch_ranking,
    launch_crossing_by_tau_pair,
    primary_arm_id = primary_arm_id
  )
  launch_run_config <- data.frame(
    phase = "phase4j_tau0_candidate_launch",
    tier = tier,
    registry_path = if (is.null(registry_path)) NA_character_ else app_prefer_repo_relative_path(registry_path),
    registry_sha256 = if (!is.null(registry_path) && file.exists(registry_path)) app_sha256_file(registry_path) else NA_character_,
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    fixture_manifest_sha256 = app_sha256_file(file.path(fixture_dir, "artifact_manifest.csv")),
    n_launch_registry_rows = nrow(launch_registry),
    n_base_scenarios = length(unique(launch_registry$base_scenario_id)),
    n_replicates = n_replicates,
    seed_base = seed_base,
    simulated_length = simulated_length,
    washout_length = washout_length,
    train_length = train_length,
    test_length = test_length,
    n_candidate_arms = nrow(arm_grid),
    primary_arm_id = primary_arm_id,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(adaptive_vb_max_iter_grid, collapse = ","),
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = if (is.finite(as.numeric(max_origins_per_scenario))) as.integer(max_origins_per_scenario) else NA_integer_,
    vb_tol = vb_tol,
    kappa = kappa,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    all_fixture_hashes_verified = all(fixture_manifest$hash_verified),
    all_phase3_manifest_hashes_verified = all(app_as_bool_vec(arm_run_manifest$manifest_hashes_verified)),
    stringsAsFactors = FALSE
  )
  phase4j_readiness_assessment <- app_joint_qvp_phase4j_assessment(
    launch_registry = launch_registry,
    fixture_manifest = fixture_manifest,
    arm_run_manifest = arm_run_manifest,
    launch_metric_summary = launch_metric_summary,
    launch_ranking = launch_ranking,
    launch_recommendation = launch_recommendation,
    launch_run_config = launch_run_config
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qvp_phase4j_readme_lines(launch_run_config, phase4j_readiness_assessment, launch_recommendation), readme_path, useBytes = TRUE)
  paths <- c(
    launch_arm_grid = app_joint_qvp_write_csv(arm_grid, file.path(out_dir, "launch_arm_grid.csv")),
    launch_registry = app_joint_qvp_write_csv(launch_registry, file.path(out_dir, "launch_registry.csv")),
    launch_run_config = app_joint_qvp_write_csv(launch_run_config, file.path(out_dir, "launch_run_config.csv")),
    launch_arm_run_manifest = app_joint_qvp_write_csv(arm_run_manifest, file.path(out_dir, "launch_arm_run_manifest.csv")),
    launch_metric_summary = app_joint_qvp_write_csv(launch_metric_summary, file.path(out_dir, "launch_metric_summary.csv")),
    launch_ranking = app_joint_qvp_write_csv(launch_ranking, file.path(out_dir, "launch_ranking.csv")),
    launch_crossing_by_arm = app_joint_qvp_write_csv(launch_crossing_by_arm, file.path(out_dir, "launch_crossing_by_arm.csv")),
    launch_crossing_by_scenario = app_joint_qvp_write_csv(launch_crossing_by_scenario, file.path(out_dir, "launch_crossing_by_scenario.csv")),
    launch_crossing_by_family = app_joint_qvp_write_csv(launch_crossing_by_family, file.path(out_dir, "launch_crossing_by_family.csv")),
    launch_crossing_by_tau_pair = app_joint_qvp_write_csv(launch_crossing_by_tau_pair, file.path(out_dir, "launch_crossing_by_tau_pair.csv")),
    launch_truth_by_tau = app_joint_qvp_write_csv(launch_truth_by_tau, file.path(out_dir, "launch_truth_by_tau.csv")),
    launch_tail_tradeoff_summary = app_joint_qvp_write_csv(launch_tail_tradeoff_summary, file.path(out_dir, "launch_tail_tradeoff_summary.csv")),
    launch_vb_runtime_summary = app_joint_qvp_write_csv(launch_vb_runtime_summary, file.path(out_dir, "launch_vb_runtime_summary.csv")),
    launch_recommendation = app_joint_qvp_write_csv(launch_recommendation, file.path(out_dir, "launch_recommendation.csv")),
    phase4j_readiness_assessment = app_joint_qvp_write_csv(phase4j_readiness_assessment, file.path(out_dir, "phase4j_readiness_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    fixture_dir = fixture_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    launch_arm_grid = arm_grid,
    launch_registry = launch_registry,
    launch_run_config = launch_run_config,
    launch_arm_run_manifest = arm_run_manifest,
    launch_metric_summary = launch_metric_summary,
    launch_ranking = launch_ranking,
    launch_crossing_by_arm = launch_crossing_by_arm,
    launch_crossing_by_scenario = launch_crossing_by_scenario,
    launch_crossing_by_family = launch_crossing_by_family,
    launch_crossing_by_tau_pair = launch_crossing_by_tau_pair,
    launch_truth_by_tau = launch_truth_by_tau,
    launch_tail_tradeoff_summary = launch_tail_tradeoff_summary,
    launch_vb_runtime_summary = launch_vb_runtime_summary,
    launch_recommendation = launch_recommendation,
    phase4j_readiness_assessment = phase4j_readiness_assessment
  )
}

app_joint_qvp_phase4j_read_launch_artifacts <- function(out_dir) {
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  read <- function(name) app_read_csv(file.path(out_dir, name))
  list(
    out_dir = out_dir,
    manifest = app_joint_qvp_phase4_manifest_with_hashes(out_dir),
    arm_grid = read("launch_arm_grid.csv"),
    registry = read("launch_registry.csv"),
    run_config = read("launch_run_config.csv"),
    arm_run_manifest = read("launch_arm_run_manifest.csv"),
    metric_summary = read("launch_metric_summary.csv"),
    ranking = read("launch_ranking.csv"),
    crossing_by_arm = read("launch_crossing_by_arm.csv"),
    crossing_by_scenario = read("launch_crossing_by_scenario.csv"),
    crossing_by_family = read("launch_crossing_by_family.csv"),
    crossing_by_tau_pair = read("launch_crossing_by_tau_pair.csv"),
    truth_by_tau = read("launch_truth_by_tau.csv"),
    tail_tradeoff = read("launch_tail_tradeoff_summary.csv"),
    vb_runtime = read("launch_vb_runtime_summary.csv"),
    recommendation = read("launch_recommendation.csv"),
    assessment = read("phase4j_readiness_assessment.csv")
  )
}

app_joint_qvp_phase4j_hit_coverage_audit <- function(arm_run_manifest) {
  rows <- list()
  for (ii in seq_len(nrow(arm_run_manifest))) {
    arm_id <- arm_run_manifest$arm_id[[ii]]
    phase3_dir <- app_joint_qvp_phase4h_phase3_dir(arm_run_manifest$phase3_out_dir[[ii]])
    hit <- app_read_csv(file.path(phase3_dir, "hit_rate_summary.csv"))
    cov <- app_read_csv(file.path(phase3_dir, "interval_coverage_summary.csv"))
    if (nrow(hit)) {
      hit$arm_id <- arm_id
      hit$metric_type <- "hit_rate"
      hit$value <- abs(hit$hit_rate_minus_tau)
      rows[[length(rows) + 1L]] <- hit[, intersect(c("arm_id", "metric_type", "scenario_id", "method", "tau", "value", "hit_rate", "hit_rate_minus_tau"), names(hit)), drop = FALSE]
    }
    if (nrow(cov)) {
      cov$arm_id <- arm_id
      cov$metric_type <- "interval_coverage"
      cov$value <- abs(cov$coverage_minus_nominal)
      rows[[length(rows) + 1L]] <- cov[, intersect(c("arm_id", "metric_type", "scenario_id", "method", "lower_tau", "upper_tau", "nominal", "value", "coverage", "coverage_minus_nominal"), names(cov)), drop = FALSE]
    }
  }
  if (!length(rows)) return(data.frame())
  app_bind_rows_fill(rows)
}

app_joint_qvp_audit_synthetic_dgp_phase4j_tau0_candidate_launch <- function(
  out_dir = app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir(),
  audit_dir = file.path(out_dir, "phase4j_launch_audit"),
  article_freeze_dir = app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  audit_dir <- normalizePath(audit_dir, mustWork = FALSE)
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  art <- app_joint_qvp_phase4j_read_launch_artifacts(out_dir)
  root_manifest_ok <- nrow(art$manifest) > 0L && all(art$manifest$hash_verified)
  nested_ok <- nrow(art$arm_run_manifest) > 0L && all(app_as_bool_vec(art$arm_run_manifest$manifest_hashes_verified))
  fixture_dir <- art$run_config$fixture_dir[[1L]]
  fixture_dir <- if (grepl("^/", fixture_dir)) fixture_dir else app_path(fixture_dir)
  fixture_manifest <- app_joint_qvp_phase4_manifest_with_hashes(fixture_dir)
  fixture_ok <- nrow(fixture_manifest) > 0L && all(fixture_manifest$hash_verified)
  nonlaunch_label <- app_joint_qvp_phase4j_contains_nonlaunch_label(
    art$registry$registry_version,
    art$registry$scenario_id,
    art$registry$validation_tier,
    art$registry$seed_role,
    art$run_config$phase,
    art$run_config$tier,
    art$recommendation$scope
  )
  selected_arm <- art$recommendation$selected_arm_id[[1L]]
  selected_manifest <- art$arm_run_manifest[art$arm_run_manifest$arm_id == selected_arm, , drop = FALSE]
  health <- data.frame(
    scope = "phase4j_tau0_candidate_launch_audit",
    launch_dir = app_prefer_repo_relative_path(out_dir),
    root_manifest_hashes_verified = root_manifest_ok,
    nested_phase3_manifest_hashes_verified = nested_ok,
    fixture_manifest_hashes_verified = fixture_ok,
    no_nonlaunch_labels = !nonlaunch_label,
    implementation_status = art$assessment$implementation_status[[1L]],
    launch_gate_status = art$assessment$gate_status[[1L]],
    total_raw_crossing_pairs = art$assessment$total_raw_crossing_pairs[[1L]],
    total_contract_crossing_pairs = art$assessment$total_contract_crossing_pairs[[1L]],
    mean_vb_max_iter_rate = art$assessment$mean_vb_max_iter_rate[[1L]],
    selected_arm_id = selected_arm,
    selected_tau0 = art$recommendation$selected_tau0[[1L]],
    audit_gate_status = if (!root_manifest_ok || !nested_ok || !fixture_ok || nonlaunch_label ||
      art$assessment$total_contract_crossing_pairs[[1L]] > 0) "fail" else "review",
    note = app_joint_qvp_ts_assessment_note(c(
      if (!root_manifest_ok) "root manifest hash verification failed",
      if (!nested_ok) "nested Phase 3 manifest hash verification failed",
      if (!fixture_ok) "fixture manifest hash verification failed",
      if (nonlaunch_label) "nonlaunch smoke/pilot labels found",
      if (art$assessment$total_contract_crossing_pairs[[1L]] > 0) "contract crossings block promotion",
      if (art$assessment$total_raw_crossing_pairs[[1L]] > 0) "raw crossings remain diagnostic review evidence",
      if (art$assessment$mean_vb_max_iter_rate[[1L]] > 0.20) "VB max-iteration rate review"
    )),
    stringsAsFactors = FALSE
  )
  decision <- data.frame(
    scope = "phase4j_tau0_decision",
    selected_arm_id = selected_arm,
    selected_tau0 = art$recommendation$selected_tau0[[1L]],
    recommendation_status = art$recommendation$recommendation_status[[1L]],
    primary_arm_id = art$recommendation$primary_arm_id[[1L]],
    best_ranked_arm_id = art$recommendation$best_ranked_arm_id[[1L]],
    selected_phase3_out_dir = if (nrow(selected_manifest)) selected_manifest$phase3_out_dir[[1L]] else NA_character_,
    selected_phase3_artifact_manifest = if (nrow(selected_manifest)) selected_manifest$phase3_artifact_manifest[[1L]] else NA_character_,
    selected_manifest_sha256 = if (nrow(selected_manifest)) selected_manifest$manifest_sha256[[1L]] else NA_character_,
    decision_status = if (health$audit_gate_status[[1L]] == "fail") "blocked" else "selected_for_article_candidate_freeze",
    rationale = art$recommendation$note[[1L]],
    stringsAsFactors = FALSE
  )
  crossing_long <- app_bind_rows_fill(list(
    cbind(summary_level = "arm", art$crossing_by_arm),
    cbind(summary_level = "scenario", art$crossing_by_scenario),
    cbind(summary_level = "family", art$crossing_by_family),
    cbind(summary_level = "tau_pair", art$crossing_by_tau_pair)
  ))
  hit_coverage <- app_joint_qvp_phase4j_hit_coverage_audit(art$arm_run_manifest)
  promotion_plan <- data.frame(
    scope = "phase4j_article_candidate_promotion",
    promotion_status = if (health$audit_gate_status[[1L]] == "fail") "blocked" else "ready_to_promote_selected_arm",
    selected_arm_id = selected_arm,
    selected_tau0 = art$recommendation$selected_tau0[[1L]],
    source_launch_dir = app_prefer_repo_relative_path(out_dir),
    selected_phase3_out_dir = decision$selected_phase3_out_dir[[1L]],
    article_freeze_dir = app_prefer_repo_relative_path(article_freeze_dir),
    requires_duplicate_compute = FALSE,
    note = "Promote selected arm artifacts from the two-arm launch unless a reviewer explicitly requires a duplicate single-arm run.",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(audit_dir, "README.md")
  writeLines(c(
    "# Joint-QVP Synthetic DGP Forecast Phase 4j Launch Audit",
    "",
    "This directory audits a completed Phase 4j tau0 candidate launch.",
    sprintf("- Launch gate: %s", health$launch_gate_status[[1L]]),
    sprintf("- Audit gate: %s", health$audit_gate_status[[1L]]),
    sprintf("- Selected arm: %s", selected_arm),
    sprintf("- Selected tau0: %s", art$recommendation$selected_tau0[[1L]]),
    "",
    "Primary files:",
    "",
    "- `phase4j_launch_health_summary.csv`",
    "- `phase4j_tau0_decision_summary.csv`",
    "- `phase4j_crossing_by_arm_scenario_family_tau.csv`",
    "- `phase4j_truth_distance_by_arm_tau.csv`",
    "- `phase4j_hit_coverage_by_arm_tau.csv`",
    "- `phase4j_vb_convergence_runtime_audit.csv`",
    "- `phase4j_article_candidate_promotion_plan.csv`"
  ), readme_path, useBytes = TRUE)
  paths <- c(
    phase4j_launch_health_summary = app_joint_qvp_write_csv(health, file.path(audit_dir, "phase4j_launch_health_summary.csv")),
    phase4j_tau0_decision_summary = app_joint_qvp_write_csv(decision, file.path(audit_dir, "phase4j_tau0_decision_summary.csv")),
    phase4j_crossing_by_arm_scenario_family_tau = app_joint_qvp_write_csv(crossing_long, file.path(audit_dir, "phase4j_crossing_by_arm_scenario_family_tau.csv")),
    phase4j_truth_distance_by_arm_tau = app_joint_qvp_write_csv(art$truth_by_tau, file.path(audit_dir, "phase4j_truth_distance_by_arm_tau.csv")),
    phase4j_hit_coverage_by_arm_tau = app_joint_qvp_write_csv(hit_coverage, file.path(audit_dir, "phase4j_hit_coverage_by_arm_tau.csv")),
    phase4j_vb_convergence_runtime_audit = app_joint_qvp_write_csv(art$vb_runtime, file.path(audit_dir, "phase4j_vb_convergence_runtime_audit.csv")),
    phase4j_article_candidate_promotion_plan = app_joint_qvp_write_csv(promotion_plan, file.path(audit_dir, "phase4j_article_candidate_promotion_plan.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(audit_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(audit_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    audit_dir = audit_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    health = health,
    decision = decision,
    promotion_plan = promotion_plan
  )
}

app_joint_qvp_phase4k_default_table_dir <- function() {
  app_path("tables")
}

app_joint_qvp_phase4k_default_figure_dir <- function() {
  app_path("figures/joint_qvp_synthetic_dgp")
}

app_joint_qvp_phase4k_resolve_path <- function(path, must_work = FALSE) {
  if (is.null(path) || !length(path) || !nzchar(as.character(path[[1L]]))) {
    stop("Phase 4k received an empty path.", call. = FALSE)
  }
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

app_joint_qvp_phase4k_manifest_status <- function(dir, source_role) {
  dir <- app_joint_qvp_phase4k_resolve_path(dir, must_work = TRUE)
  manifest <- app_joint_qvp_phase4_manifest_with_hashes(dir)
  data.frame(
    source_role = source_role,
    source_dir = app_prefer_repo_relative_path(dir),
    manifest_path = app_prefer_repo_relative_path(file.path(dir, "artifact_manifest.csv")),
    n_manifest_rows = nrow(manifest),
    n_missing_files = sum(!manifest$file_exists),
    n_hash_mismatches = sum(manifest$file_exists & !manifest$hash_verified),
    all_hashes_verified = all(manifest$hash_verified),
    manifest_sha256 = app_sha256_file(file.path(dir, "artifact_manifest.csv")),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4k_manifest_from_paths <- function(paths, base_dir) {
  paths <- paths[file.exists(paths)]
  rel <- vapply(paths, function(path) {
    abs <- normalizePath(path, mustWork = TRUE)
    base <- normalizePath(base_dir, mustWork = TRUE)
    prefix <- paste0(base, .Platform$file.sep)
    if (startsWith(abs, prefix)) sub(prefix, "", abs, fixed = TRUE) else basename(abs)
  }, character(1L))
  data.frame(
    label = names(paths),
    relative_path = rel,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_phase4k_base_scenario_id <- function(scenario_id) {
  sub("__tau0_candidate_launch_r[0-9]+$", "", as.character(scenario_id))
}

app_joint_qvp_phase4k_scenario_truth_summary <- function(truth) {
  if (!nrow(truth)) return(data.frame())
  app_check_required_columns(
    truth,
    c("scenario_id", "tau", "n_forecasts", "mae_to_truth", "rmse_to_truth", "max_abs_error_to_truth"),
    "Phase 4k selected-arm truth comparison"
  )
  truth$base_scenario_id <- app_joint_qvp_phase4k_base_scenario_id(truth$scenario_id)
  rows <- lapply(split(truth, truth$base_scenario_id), function(block) {
    data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      n_scenarios = length(unique(block$scenario_id)),
      n_tau = length(unique(block$tau)),
      n_forecasts = sum(block$n_forecasts, na.rm = TRUE),
      mae_to_truth_mean = mean(block$mae_to_truth, na.rm = TRUE),
      rmse_to_truth_mean = mean(block$rmse_to_truth, na.rm = TRUE),
      max_abs_error_to_truth = max(block$max_abs_error_to_truth, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(-out$mae_to_truth_mean), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_joint_qvp_phase4k_adjustment_events <- function(adjustment) {
  if (!nrow(adjustment)) return(data.frame())
  app_check_required_columns(
    adjustment,
    c("scenario_id", "origin_index", "forecast_time_index", "n_raw_crossing_pairs", "max_abs_adjustment", "affected_tau_pairs"),
    "Phase 4k monotone adjustment table"
  )
  events <- adjustment[adjustment$n_raw_crossing_pairs > 0, , drop = FALSE]
  if (!nrow(events)) return(events)
  events$base_scenario_id <- app_joint_qvp_phase4k_base_scenario_id(events$scenario_id)
  rownames(events) <- NULL
  events
}

app_joint_qvp_phase4k_adjustment_summary <- function(events) {
  if (!nrow(events)) {
    return(data.frame(
      base_scenario_id = character(),
      affected_tau_pairs = character(),
      raw_crossing_pairs = integer(),
      raw_crossing_origins = integer(),
      max_abs_adjustment = numeric(),
      mean_abs_adjustment = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  groups <- split(events, paste(events$base_scenario_id, events$affected_tau_pairs, sep = "\r"))
  rows <- lapply(groups, function(block) {
    data.frame(
      base_scenario_id = block$base_scenario_id[[1L]],
      affected_tau_pairs = block$affected_tau_pairs[[1L]],
      raw_crossing_pairs = sum(block$n_raw_crossing_pairs, na.rm = TRUE),
      raw_crossing_origins = nrow(block),
      max_abs_adjustment = max(block$max_abs_adjustment, na.rm = TRUE),
      mean_abs_adjustment = mean(block$max_abs_adjustment, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(-out$raw_crossing_pairs, -out$max_abs_adjustment), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_joint_qvp_phase4k_freeze_readme_lines <- function(decision) {
  c(
    "# Joint-QVP Synthetic DGP Phase 4k Article-Candidate Freeze",
    "",
    "This directory freezes the selected Phase 4j tau0 candidate launch arm as a storage-light article-candidate synthetic DGP forecast validation artifact.",
    "No new model fitting is performed in this stage.",
    "",
    sprintf("- Selected arm: %s", decision$selected_arm_id[[1L]]),
    sprintf("- Selected tau0: %s", decision$selected_tau0[[1L]]),
    sprintf("- Freeze gate: %s", decision$freeze_gate_status[[1L]]),
    sprintf("- Contract crossing pairs: %s", decision$selected_contract_crossing_pairs[[1L]]),
    sprintf("- Raw crossing pairs: %s", decision$selected_raw_crossing_pairs[[1L]]),
    "",
    "Primary files:",
    "",
    "- `freeze_decision_summary.csv`: selected-arm decision and freeze gate.",
    "- `freeze_source_manifest_verification.csv`: launch, fixture, audit, and selected-arm manifest checks.",
    "- `freeze_tau0_arm_comparison.csv`: two-arm Phase 4j comparison retained for decision provenance.",
    "- `freeze_selected_arm_metric_summary.csv`: selected-arm forecast metric summary.",
    "- `freeze_selected_arm_truth_by_tau.csv`: selected-arm truth-distance metrics by tau.",
    "- `freeze_selected_arm_scenario_truth_summary.csv`: selected-arm truth-distance metrics by base scenario.",
    "- `freeze_selected_arm_crossing_summary.csv`: raw and contract crossing diagnostics.",
    "- `freeze_selected_arm_hit_coverage_summary.csv`: selected-arm hit-rate and interval-coverage diagnostics.",
    "- `freeze_selected_arm_vb_runtime_summary.csv`: selected-arm convergence/runtime diagnostics.",
    "- `freeze_selected_arm_scenario_assessment.csv`: selected-arm scenario gates.",
    "- `freeze_selected_arm_monotone_adjustment_events.csv`: raw crossing origins requiring monotone adjustment.",
    "- `freeze_selected_arm_monotone_adjustment_summary.csv`: compact adjustment summary.",
    "- `freeze_large_file_registry.csv`: large selected-arm files referenced by source path and SHA-256 hash.",
    "- `artifact_manifest.csv`: SHA-256 hashes for this freeze directory.",
    "",
    "Interpretation:",
    "",
    "Contract forecast quantiles are noncrossing and are used for scoring. Raw forecast quantiles remain preserved through the source artifact references and summarized as diagnostic review evidence."
  )
}

app_joint_qvp_freeze_synthetic_dgp_phase4k_article_candidate <- function(
  launch_dir = app_joint_qvp_default_synthetic_dgp_phase4j_launch_dir(),
  audit_dir = file.path(launch_dir, "phase4j_launch_audit"),
  freeze_dir = app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir(),
  copy_large_forecast_files = FALSE,
  expected_selected_arm = "tau0_0p15_comparator",
  allow_selected_arm_override = FALSE
) {
  launch_dir <- app_joint_qvp_phase4k_resolve_path(launch_dir, must_work = TRUE)
  audit_dir <- app_joint_qvp_phase4k_resolve_path(audit_dir, must_work = TRUE)
  freeze_dir <- app_joint_qvp_phase4k_resolve_path(freeze_dir, must_work = FALSE)
  dir.create(freeze_dir, recursive = TRUE, showWarnings = FALSE)

  exit_file <- file.path(launch_dir, "phase4j_launch.exitcode")
  if (!file.exists(exit_file)) stop("Phase 4k freeze requires phase4j_launch.exitcode.", call. = FALSE)
  exit_code <- trimws(readLines(exit_file, warn = FALSE)[1L])
  if (!identical(exit_code, "0")) stop(sprintf("Phase 4j launch exit code is not 0: %s", exit_code), call. = FALSE)

  art <- app_joint_qvp_phase4j_read_launch_artifacts(launch_dir)
  health <- app_read_csv(file.path(audit_dir, "phase4j_launch_health_summary.csv"))
  decision <- app_read_csv(file.path(audit_dir, "phase4j_tau0_decision_summary.csv"))
  promotion <- app_read_csv(file.path(audit_dir, "phase4j_article_candidate_promotion_plan.csv"))
  audit_crossing <- app_read_csv(file.path(audit_dir, "phase4j_crossing_by_arm_scenario_family_tau.csv"))
  audit_hit_coverage <- app_read_csv(file.path(audit_dir, "phase4j_hit_coverage_by_arm_tau.csv"))
  audit_truth_by_tau <- app_read_csv(file.path(audit_dir, "phase4j_truth_distance_by_arm_tau.csv"))
  audit_vb_runtime <- app_read_csv(file.path(audit_dir, "phase4j_vb_convergence_runtime_audit.csv"))

  selected_arm <- as.character(decision$selected_arm_id[[1L]])
  selected_tau0 <- as.numeric(decision$selected_tau0[[1L]])
  if (nzchar(as.character(expected_selected_arm[[1L]])) &&
      !identical(selected_arm, as.character(expected_selected_arm[[1L]])) &&
      !allow_selected_arm_override) {
    stop(sprintf("Selected arm '%s' does not match expected Phase 4k arm '%s'.", selected_arm, expected_selected_arm), call. = FALSE)
  }

  selected_manifest_row <- art$arm_run_manifest[art$arm_run_manifest$arm_id == selected_arm, , drop = FALSE]
  if (nrow(selected_manifest_row) != 1L) stop("Could not identify exactly one selected Phase 3 arm manifest row.", call. = FALSE)
  selected_phase3_dir <- app_joint_qvp_phase4k_resolve_path(selected_manifest_row$phase3_out_dir[[1L]], must_work = TRUE)
  fixture_dir <- app_joint_qvp_phase4k_resolve_path(art$run_config$fixture_dir[[1L]], must_work = TRUE)

  source_manifest_verification <- app_bind_rows_fill(list(
    app_joint_qvp_phase4k_manifest_status(launch_dir, "phase4j_launch_root"),
    app_joint_qvp_phase4k_manifest_status(fixture_dir, "phase1_launch_fixtures"),
    app_joint_qvp_phase4k_manifest_status(selected_phase3_dir, "selected_phase3_forecast_arm"),
    app_joint_qvp_phase4k_manifest_status(audit_dir, "phase4j_launch_audit")
  ))
  if (!all(app_as_bool_vec(source_manifest_verification$all_hashes_verified))) {
    stop("Phase 4k source manifest verification failed.", call. = FALSE)
  }

  selected_metric <- art$metric_summary[art$metric_summary$arm_id == selected_arm, , drop = FALSE]
  if (nrow(selected_metric) != 1L) stop("Could not identify exactly one selected metric row.", call. = FALSE)
  if (selected_metric$contract_crossing_pairs[[1L]] != 0) {
    stop("Selected arm has contract forecast crossings.", call. = FALSE)
  }
  required_finite <- c("truth_mae_mean", "truth_rmse_mean", "pinball_mean", "wis_mean", "crps_grid_mean")
  missing_finite <- setdiff(required_finite, names(selected_metric))
  if (length(missing_finite)) stop(sprintf("Selected metric row is missing: %s", paste(missing_finite, collapse = ", ")), call. = FALSE)
  if (any(!is.finite(as.numeric(unlist(selected_metric[required_finite], use.names = FALSE))))) {
    stop("Selected metric row contains nonfinite score summaries.", call. = FALSE)
  }

  nonlaunch_label <- app_joint_qvp_phase4j_contains_nonlaunch_label(
    art$registry$registry_version,
    art$registry$scenario_id,
    art$registry$validation_tier,
    art$registry$seed_role,
    art$run_config$phase,
    art$run_config$tier,
    decision$scope,
    promotion$scope
  )
  if (nonlaunch_label) stop("Phase 4k freeze refuses smoke/pilot labels in source launch metadata.", call. = FALSE)

  selected_truth_by_tau <- audit_truth_by_tau[
    audit_truth_by_tau$screen_id == selected_arm | abs(audit_truth_by_tau$tau0 - selected_tau0) < 1.0e-12,
    , drop = FALSE
  ]
  selected_hit_coverage <- audit_hit_coverage[audit_hit_coverage$arm_id == selected_arm, , drop = FALSE]
  selected_vb_runtime <- audit_vb_runtime[audit_vb_runtime$arm_id == selected_arm, , drop = FALSE]
  selected_crossing <- audit_crossing[
    audit_crossing$arm_id == selected_arm |
      audit_crossing$screen_id == selected_arm |
      (!is.na(audit_crossing$tau0) & abs(audit_crossing$tau0 - selected_tau0) < 1.0e-12),
    , drop = FALSE
  ]

  scenario_assessment <- app_read_csv(file.path(selected_phase3_dir, "forecast_validation_assessment.csv"))
  truth_comparison <- app_read_csv(file.path(selected_phase3_dir, "forecast_truth_comparison.csv"))
  monotone_adjustment <- app_read_csv(file.path(selected_phase3_dir, "forecast_monotone_adjustment.csv"))
  adjustment_events <- app_joint_qvp_phase4k_adjustment_events(monotone_adjustment)
  adjustment_summary <- app_joint_qvp_phase4k_adjustment_summary(adjustment_events)
  scenario_truth_summary <- app_joint_qvp_phase4k_scenario_truth_summary(truth_comparison)

  phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(selected_phase3_dir)
  large_registry <- phase3_manifest
  large_registry$source_role <- "selected_phase3_forecast_arm"
  large_registry$source_path <- vapply(large_registry$absolute_path, app_prefer_repo_relative_path, character(1L))
  large_registry$source_sha256 <- large_registry$observed_sha256
  large_registry$is_large_or_primary_forecast_file <- large_registry$size_bytes > 5e6 |
    large_registry$relative_path %in% c(
      "forecast_quantiles_raw.csv",
      "forecast_quantiles.csv",
      "forecast_truth_comparison.csv",
      "forecast_origin_config.csv",
      "forecast_monotone_adjustment.csv"
    )
  large_registry$storage_policy <- ifelse(
    copy_large_forecast_files & large_registry$is_large_or_primary_forecast_file,
    "copied_to_freeze",
    "referenced_by_hash"
  )
  large_registry$freeze_relative_path <- NA_character_
  copied_paths <- character()
  if (copy_large_forecast_files && any(large_registry$is_large_or_primary_forecast_file)) {
    copy_dir <- file.path(freeze_dir, "selected_phase3_forecast_files")
    dir.create(copy_dir, recursive = TRUE, showWarnings = FALSE)
    for (ii in which(large_registry$is_large_or_primary_forecast_file)) {
      source_path <- large_registry$absolute_path[[ii]]
      dest_path <- file.path(copy_dir, large_registry$relative_path[[ii]])
      dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(source_path, dest_path, overwrite = TRUE)) {
        stop(sprintf("Failed to copy selected Phase 3 file: %s", source_path), call. = FALSE)
      }
      copied_paths[paste0("copied_", large_registry$label[[ii]])] <- normalizePath(dest_path, mustWork = TRUE)
      large_registry$freeze_relative_path[[ii]] <- sub(
        paste0(normalizePath(freeze_dir, mustWork = TRUE), .Platform$file.sep),
        "",
        normalizePath(dest_path, mustWork = TRUE),
        fixed = TRUE
      )
    }
  }
  large_registry <- large_registry[, c(
    "label", "relative_path", "size_bytes", "source_role", "source_path", "source_sha256",
    "file_exists", "hash_verified", "is_large_or_primary_forecast_file",
    "storage_policy", "freeze_relative_path"
  ), drop = FALSE]

  arm_comparison <- art$metric_summary
  arm_comparison$selected_for_freeze <- arm_comparison$arm_id == selected_arm

  freeze_gate_status <- if (selected_metric$contract_crossing_pairs[[1L]] > 0) {
    "fail"
  } else if (selected_metric$raw_crossing_pairs[[1L]] > 0 ||
      !identical(health$audit_gate_status[[1L]], "pass")) {
    "review"
  } else {
    "pass"
  }
  freeze_decision <- data.frame(
    scope = "phase4k_article_candidate_freeze",
    freeze_status = if (identical(freeze_gate_status, "fail")) "blocked" else "ready",
    freeze_gate_status = freeze_gate_status,
    selected_arm_id = selected_arm,
    selected_tau0 = selected_tau0,
    selected_phase3_out_dir = app_prefer_repo_relative_path(selected_phase3_dir),
    selected_phase3_artifact_manifest = app_prefer_repo_relative_path(file.path(selected_phase3_dir, "artifact_manifest.csv")),
    selected_phase3_manifest_sha256 = app_sha256_file(file.path(selected_phase3_dir, "artifact_manifest.csv")),
    source_launch_dir = app_prefer_repo_relative_path(launch_dir),
    source_audit_dir = app_prefer_repo_relative_path(audit_dir),
    source_fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    selected_contract_crossing_pairs = selected_metric$contract_crossing_pairs[[1L]],
    selected_raw_crossing_pairs = selected_metric$raw_crossing_pairs[[1L]],
    selected_truth_mae_mean = selected_metric$truth_mae_mean[[1L]],
    selected_truth_rmse_mean = selected_metric$truth_rmse_mean[[1L]],
    selected_pinball_mean = selected_metric$pinball_mean[[1L]],
    selected_wis_mean = selected_metric$wis_mean[[1L]],
    selected_crps_grid_mean = selected_metric$crps_grid_mean[[1L]],
    selected_vb_max_iter_rate = selected_metric$vb_max_iter_rate[[1L]],
    selected_runtime_total_sec = selected_metric$runtime_total_sec[[1L]],
    source_launch_gate_status = health$launch_gate_status[[1L]],
    source_audit_gate_status = health$audit_gate_status[[1L]],
    requires_duplicate_compute = FALSE,
    copy_large_forecast_files = as.logical(copy_large_forecast_files),
    note = "Selected Phase 4j arm is frozen without duplicate compute; raw crossings remain diagnostic review evidence.",
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(freeze_dir, "README.md")
  writeLines(app_joint_qvp_phase4k_freeze_readme_lines(freeze_decision), readme_path, useBytes = TRUE)
  paths <- c(
    freeze_decision_summary = app_joint_qvp_write_csv(freeze_decision, file.path(freeze_dir, "freeze_decision_summary.csv")),
    freeze_source_manifest_verification = app_joint_qvp_write_csv(source_manifest_verification, file.path(freeze_dir, "freeze_source_manifest_verification.csv")),
    freeze_launch_run_config = app_joint_qvp_write_csv(art$run_config, file.path(freeze_dir, "freeze_launch_run_config.csv")),
    freeze_tau0_arm_comparison = app_joint_qvp_write_csv(arm_comparison, file.path(freeze_dir, "freeze_tau0_arm_comparison.csv")),
    freeze_selected_arm_metric_summary = app_joint_qvp_write_csv(selected_metric, file.path(freeze_dir, "freeze_selected_arm_metric_summary.csv")),
    freeze_selected_arm_truth_by_tau = app_joint_qvp_write_csv(selected_truth_by_tau, file.path(freeze_dir, "freeze_selected_arm_truth_by_tau.csv")),
    freeze_selected_arm_scenario_truth_summary = app_joint_qvp_write_csv(scenario_truth_summary, file.path(freeze_dir, "freeze_selected_arm_scenario_truth_summary.csv")),
    freeze_selected_arm_crossing_summary = app_joint_qvp_write_csv(selected_crossing, file.path(freeze_dir, "freeze_selected_arm_crossing_summary.csv")),
    freeze_selected_arm_hit_coverage_summary = app_joint_qvp_write_csv(selected_hit_coverage, file.path(freeze_dir, "freeze_selected_arm_hit_coverage_summary.csv")),
    freeze_selected_arm_vb_runtime_summary = app_joint_qvp_write_csv(selected_vb_runtime, file.path(freeze_dir, "freeze_selected_arm_vb_runtime_summary.csv")),
    freeze_selected_arm_scenario_assessment = app_joint_qvp_write_csv(scenario_assessment, file.path(freeze_dir, "freeze_selected_arm_scenario_assessment.csv")),
    freeze_selected_arm_monotone_adjustment_events = app_joint_qvp_write_csv(adjustment_events, file.path(freeze_dir, "freeze_selected_arm_monotone_adjustment_events.csv")),
    freeze_selected_arm_monotone_adjustment_summary = app_joint_qvp_write_csv(adjustment_summary, file.path(freeze_dir, "freeze_selected_arm_monotone_adjustment_summary.csv")),
    freeze_large_file_registry = app_joint_qvp_write_csv(large_registry, file.path(freeze_dir, "freeze_large_file_registry.csv")),
    selected_phase3_artifact_manifest = app_joint_qvp_write_csv(phase3_manifest, file.path(freeze_dir, "selected_phase3_artifact_manifest.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(freeze_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  if (length(copied_paths)) paths <- c(paths, copied_paths)
  manifest <- app_joint_qvp_phase4k_manifest_from_paths(paths, freeze_dir)
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(freeze_dir, "artifact_manifest.csv"))
  list(
    freeze_dir = freeze_dir,
    launch_dir = launch_dir,
    audit_dir = audit_dir,
    selected_phase3_dir = selected_phase3_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    freeze_decision = freeze_decision,
    source_manifest_verification = source_manifest_verification,
    selected_metric = selected_metric
  )
}

app_joint_qvp_phase4k_latex_escape <- function(x) {
  x <- as.character(x)
  replacements <- c(
    "&" = "\\&",
    "%" = "\\%",
    "$" = "\\$",
    "#" = "\\#",
    "_" = "\\_",
    "{" = "\\{",
    "}" = "\\}"
  )
  for (pat in names(replacements)) x <- gsub(pat, replacements[[pat]], x, fixed = TRUE)
  x
}

app_joint_qvp_phase4k_format_cell <- function(x) {
  if (length(x) != 1L) x <- x[[1L]]
  if (is.logical(x)) return(ifelse(is.na(x), "", ifelse(x, "TRUE", "FALSE")))
  if (is.numeric(x) || is.integer(x)) {
    if (!is.finite(x)) return("")
    if (abs(x - round(x)) < 1.0e-12 && abs(x) >= 10) return(formatC(x, format = "f", digits = 0, big.mark = ","))
    if (abs(x) >= 100) return(formatC(x, format = "f", digits = 1, big.mark = ","))
    if (abs(x) >= 1) return(formatC(x, format = "f", digits = 3))
    return(formatC(x, format = "f", digits = 4))
  }
  app_joint_qvp_phase4k_latex_escape(x)
}

app_joint_qvp_phase4k_write_latex_table <- function(df, path, caption, label) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!nrow(df)) df <- data.frame(message = "No rows available", stringsAsFactors = FALSE)
  header <- app_joint_qvp_phase4k_latex_escape(names(df))
  rows <- apply(df, 1L, function(row) {
    paste(vapply(seq_along(row), function(ii) app_joint_qvp_phase4k_format_cell(row[[ii]]), character(1L)), collapse = " & ")
  })
  align <- paste(rep("l", ncol(df)), collapse = "")
  lines <- c(
    sprintf("%% Generated by Phase 4k article asset builder. SHA source is recorded in joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv."),
    "\\begin{table}[t]",
    "\\centering",
    "\\small",
    sprintf("\\begin{tabular}{@{}%s@{}}", align),
    "\\toprule",
    paste(header, collapse = " & "),
    "\\\\",
    "\\midrule",
    paste0(rows, " \\\\"),
    "\\bottomrule",
    "\\end{tabular}",
    sprintf("\\caption{%s}", app_joint_qvp_phase4k_latex_escape(caption)),
    sprintf("\\label{%s}", label),
    "\\end{table}"
  )
  writeLines(lines, path, useBytes = TRUE)
  normalizePath(path, mustWork = TRUE)
}

app_joint_qvp_phase4k_png_plot <- function(path, width = 1800, height = 1200, res = 180, expr) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::png(path, width = width, height = height, res = res, type = "cairo")
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  force(expr)
  normalizePath(path, mustWork = TRUE)
}

app_joint_qvp_build_synthetic_dgp_phase4k_article_assets <- function(
  freeze_dir = app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir(),
  table_dir = app_joint_qvp_phase4k_default_table_dir(),
  figure_dir = app_joint_qvp_phase4k_default_figure_dir()
) {
  freeze_dir <- app_joint_qvp_phase4k_resolve_path(freeze_dir, must_work = TRUE)
  table_dir <- app_joint_qvp_phase4k_resolve_path(table_dir, must_work = FALSE)
  figure_dir <- app_joint_qvp_phase4k_resolve_path(figure_dir, must_work = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  freeze_manifest <- app_joint_qvp_phase4_manifest_with_hashes(freeze_dir)
  if (!all(freeze_manifest$hash_verified)) stop("Phase 4k freeze manifest failed verification.", call. = FALSE)

  read_freeze <- function(name) app_read_csv(file.path(freeze_dir, name))
  decision <- read_freeze("freeze_decision_summary.csv")
  run_config <- read_freeze("freeze_launch_run_config.csv")
  arm_comparison <- read_freeze("freeze_tau0_arm_comparison.csv")
  selected_metric <- read_freeze("freeze_selected_arm_metric_summary.csv")
  truth_by_tau <- read_freeze("freeze_selected_arm_truth_by_tau.csv")
  scenario_truth <- read_freeze("freeze_selected_arm_scenario_truth_summary.csv")
  crossing <- read_freeze("freeze_selected_arm_crossing_summary.csv")
  hit_coverage <- read_freeze("freeze_selected_arm_hit_coverage_summary.csv")
  vb_runtime <- read_freeze("freeze_selected_arm_vb_runtime_summary.csv")
  adjustment_summary <- read_freeze("freeze_selected_arm_monotone_adjustment_summary.csv")

  protocol_table <- data.frame(
    item = c(
      "Phase", "Selected arm", "Selected tau0", "Scenarios", "Replicates",
      "Forecast origins per arm", "Train length", "Test length", "VB max iter",
      "Adaptive VB grid", "Refit stride", "Origin stride", "Freeze gate"
    ),
    value = c(
      "Phase 4k article-candidate freeze",
      decision$selected_arm_id[[1L]],
      decision$selected_tau0[[1L]],
      run_config$n_base_scenarios[[1L]],
      run_config$n_replicates[[1L]],
      selected_metric$n_forecast_origins[[1L]],
      run_config$train_length[[1L]],
      run_config$test_length[[1L]],
      run_config$vb_max_iter[[1L]],
      run_config$adaptive_vb_max_iter_grid[[1L]],
      run_config$refit_stride[[1L]],
      run_config$forecast_origin_stride[[1L]],
      decision$freeze_gate_status[[1L]]
    ),
    stringsAsFactors = FALSE
  )
  tau0_table <- arm_comparison[, intersect(c(
    "arm_id", "tau0", "selected_for_freeze", "raw_crossing_pairs", "contract_crossing_pairs",
    "truth_mae_mean", "truth_rmse_mean", "pinball_mean", "wis_mean", "crps_grid_mean",
    "vb_max_iter_rate", "runtime_total_sec", "scenario_pass_count", "scenario_review_count", "scenario_fail_count"
  ), names(arm_comparison)), drop = FALSE]
  scores_table <- selected_metric[, intersect(c(
    "arm_id", "tau0", "n_scenarios", "n_forecast_origins", "truth_mae_mean", "truth_rmse_mean",
    "pinball_mean", "wis_mean", "crps_grid_mean", "mean_abs_hit_rate_error",
    "max_abs_hit_rate_error", "scenario_pass_count", "scenario_review_count", "scenario_fail_count"
  ), names(selected_metric)), drop = FALSE]
  truth_tau_table <- truth_by_tau[, intersect(c(
    "tau", "n_scenarios", "n_forecasts", "mae_to_truth_mean", "rmse_to_truth_mean",
    "bias_to_truth_mean", "max_abs_error_to_truth"
  ), names(truth_by_tau)), drop = FALSE]
  scenario_table <- scenario_truth[, intersect(c(
    "base_scenario_id", "n_scenarios", "mae_to_truth_mean", "rmse_to_truth_mean", "max_abs_error_to_truth"
  ), names(scenario_truth)), drop = FALSE]
  crossing_table <- adjustment_summary
  if (!nrow(crossing_table)) {
    crossing_table <- data.frame(
      base_scenario_id = "none",
      affected_tau_pairs = "none",
      raw_crossing_pairs = 0L,
      raw_crossing_origins = 0L,
      max_abs_adjustment = 0,
      mean_abs_adjustment = 0,
      stringsAsFactors = FALSE
    )
  }
  runtime_table <- vb_runtime[, intersect(c(
    "arm_id", "tau0", "vb_refit_count", "vb_max_iter_count", "vb_max_iter_rate",
    "runtime_total_sec", "runtime_refit_sec", "runtime_ratio", "screen_status"
  ), names(vb_runtime)), drop = FALSE]

  table_paths <- c(
    protocol = app_joint_qvp_phase4k_write_latex_table(
      protocol_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_protocol.tex"),
      "Phase 4k joint-QVP synthetic DGP article-candidate forecast validation protocol.",
      "tab:joint-qvp-phase4k-protocol"
    ),
    tau0_decision = app_joint_qvp_phase4k_write_latex_table(
      tau0_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_tau0_decision.tex"),
      "Phase 4j tau0 launch comparison used for the Phase 4k article-candidate freeze.",
      "tab:joint-qvp-phase4k-tau0-decision"
    ),
    selected_forecast_scores = app_joint_qvp_phase4k_write_latex_table(
      scores_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_selected_forecast_scores.tex"),
      "Selected-arm forecast scores for the joint-QVP synthetic DGP validation.",
      "tab:joint-qvp-phase4k-selected-scores"
    ),
    selected_truth_by_tau = app_joint_qvp_phase4k_write_latex_table(
      truth_tau_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_selected_truth_by_tau.tex"),
      "Selected-arm forecast quantile distance to true conditional quantiles by tau.",
      "tab:joint-qvp-phase4k-truth-by-tau"
    ),
    selected_scenario_summary = app_joint_qvp_phase4k_write_latex_table(
      scenario_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_selected_scenario_summary.tex"),
      "Selected-arm forecast quantile distance to true conditional quantiles by base scenario.",
      "tab:joint-qvp-phase4k-scenario-summary"
    ),
    crossing_diagnostics = app_joint_qvp_phase4k_write_latex_table(
      crossing_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_crossing_diagnostics.tex"),
      "Selected-arm raw crossing diagnostics before the monotone forecast contract.",
      "tab:joint-qvp-phase4k-crossing-diagnostics"
    ),
    runtime_convergence = app_joint_qvp_phase4k_write_latex_table(
      runtime_table,
      file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_runtime_convergence.tex"),
      "Selected-arm VB convergence and runtime diagnostics.",
      "tab:joint-qvp-phase4k-runtime-convergence"
    )
  )

  figure_paths <- character()
  figure_paths[["truth_error_by_tau"]] <- app_joint_qvp_phase4k_png_plot(
    file.path(figure_dir, "phase4k_truth_error_by_tau.png"),
    expr = {
      graphics::par(mar = c(4.4, 4.7, 2.8, 1.2))
      yr <- range(c(truth_by_tau$mae_to_truth_mean, truth_by_tau$rmse_to_truth_mean), finite = TRUE)
      graphics::plot(truth_by_tau$tau, truth_by_tau$mae_to_truth_mean, type = "b", pch = 16,
        col = "#0072B2", lwd = 2.2, ylim = yr * c(0.92, 1.08),
        xlab = "Target tau", ylab = "Distance to true conditional quantile",
        main = "Selected-arm truth error by tau")
      graphics::lines(truth_by_tau$tau, truth_by_tau$rmse_to_truth_mean, type = "b", pch = 17, col = "#D55E00", lwd = 2.2)
      graphics::grid(col = "grey86")
      graphics::legend("topleft", legend = c("MAE", "RMSE"), col = c("#0072B2", "#D55E00"), pch = c(16, 17), lwd = 2.2, bty = "n")
    }
  )
  figure_paths[["scenario_truth_error"]] <- app_joint_qvp_phase4k_png_plot(
    file.path(figure_dir, "phase4k_scenario_truth_error.png"),
    height = 1350,
    expr = {
      ord <- order(scenario_truth$mae_to_truth_mean)
      graphics::par(mar = c(4.3, 11.5, 2.8, 1.1))
      graphics::barplot(scenario_truth$mae_to_truth_mean[ord],
        names.arg = scenario_truth$base_scenario_id[ord],
        horiz = TRUE, las = 1, col = "#009E73", border = NA,
        xlab = "Mean absolute error to true quantile",
        main = "Selected-arm truth error by scenario")
      graphics::grid(nx = NULL, ny = NA, col = "grey88")
    }
  )
  figure_paths[["raw_crossing_adjustments"]] <- app_joint_qvp_phase4k_png_plot(
    file.path(figure_dir, "phase4k_raw_crossing_adjustments.png"),
    height = 1300,
    expr = {
      dat <- adjustment_summary
      if (!nrow(dat)) dat <- data.frame(base_scenario_id = "none", affected_tau_pairs = "none", raw_crossing_pairs = 0, max_abs_adjustment = 0)
      dat$label <- paste(dat$base_scenario_id, dat$affected_tau_pairs, sep = "\n")
      ord <- order(dat$raw_crossing_pairs, dat$max_abs_adjustment)
      graphics::par(mar = c(4.5, 12, 2.8, 1.2))
      graphics::barplot(dat$raw_crossing_pairs[ord], names.arg = dat$label[ord],
        horiz = TRUE, las = 1, col = "#CC79A7", border = NA,
        xlab = "Raw crossing pairs before monotone contract",
        main = "Selected-arm raw crossing diagnostics")
      graphics::grid(nx = NULL, ny = NA, col = "grey88")
    }
  )
  figure_paths[["hit_coverage_by_tau"]] <- app_joint_qvp_phase4k_png_plot(
    file.path(figure_dir, "phase4k_hit_coverage_by_tau.png"),
    height = 1350,
    expr = {
      graphics::par(mfrow = c(2, 1), mar = c(4.3, 4.7, 2.6, 1.2))
      hit <- hit_coverage[hit_coverage$metric_type == "hit_rate", , drop = FALSE]
      if (nrow(hit)) {
        agg <- aggregate(value ~ tau, hit, mean, na.rm = TRUE)
        graphics::plot(agg$tau, agg$value, type = "b", pch = 16, lwd = 2.2, col = "#0072B2",
          xlab = "Target tau", ylab = "Mean absolute hit-rate error",
          main = "Hit-rate error by tau")
        graphics::grid(col = "grey86")
      } else graphics::plot.new()
      cov <- hit_coverage[hit_coverage$metric_type == "interval_coverage", , drop = FALSE]
      if (nrow(cov)) {
        agg <- aggregate(value ~ nominal, cov, mean, na.rm = TRUE)
        graphics::barplot(agg$value, names.arg = agg$nominal, col = "#56B4E9", border = NA,
          xlab = "Nominal interval", ylab = "Mean absolute coverage error",
          main = "Interval coverage error")
        graphics::grid(nx = NA, ny = NULL, col = "grey86")
      } else graphics::plot.new()
    }
  )
  figure_paths[["runtime_convergence_figure"]] <- app_joint_qvp_phase4k_png_plot(
    file.path(figure_dir, "phase4k_runtime_convergence.png"),
    expr = {
      graphics::par(mfrow = c(1, 2), mar = c(6.2, 4.8, 2.8, 1.1))
      graphics::barplot(arm_comparison$runtime_total_sec / 3600,
        names.arg = arm_comparison$arm_id, las = 2, col = ifelse(arm_comparison$selected_for_freeze, "#009E73", "grey70"),
        border = NA, ylab = "Runtime hours", main = "Runtime by tau0 arm")
      graphics::grid(nx = NA, ny = NULL, col = "grey88")
      graphics::barplot(arm_comparison$vb_max_iter_rate,
        names.arg = arm_comparison$arm_id, las = 2, col = ifelse(arm_comparison$selected_for_freeze, "#D55E00", "grey70"),
        border = NA, ylab = "VB max-iteration rate", main = "VB convergence review rate")
      graphics::grid(nx = NA, ny = NULL, col = "grey88")
    }
  )

  asset_paths <- c(table_paths, figure_paths)
  asset_manifest <- data.frame(
    label = names(asset_paths),
    artifact_type = ifelse(names(asset_paths) %in% names(table_paths), "table", "figure"),
    path = vapply(asset_paths, app_prefer_repo_relative_path, character(1L)),
    size_bytes = as.numeric(file.info(asset_paths)$size),
    sha256 = vapply(asset_paths, app_sha256_file, character(1L)),
    source_freeze_dir = app_prefer_repo_relative_path(freeze_dir),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(asset_manifest, file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv"))
  list(
    freeze_dir = freeze_dir,
    table_dir = table_dir,
    figure_dir = figure_dir,
    paths = c(asset_paths, asset_manifest = manifest_path),
    asset_manifest = asset_manifest
  )
}

app_joint_qvp_audit_synthetic_dgp_phase4k_article_assets <- function(
  freeze_dir = app_joint_qvp_default_synthetic_dgp_phase4j_freeze_dir(),
  table_dir = app_joint_qvp_phase4k_default_table_dir(),
  figure_dir = app_joint_qvp_phase4k_default_figure_dir(),
  audit_dir = file.path(freeze_dir, "phase4k_article_asset_audit"),
  expected_selected_arm = "tau0_0p15_comparator",
  expected_selected_tau0 = 0.15,
  allow_selected_arm_override = FALSE
) {
  freeze_dir <- app_joint_qvp_phase4k_resolve_path(freeze_dir, must_work = TRUE)
  table_dir <- app_joint_qvp_phase4k_resolve_path(table_dir, must_work = TRUE)
  figure_dir <- app_joint_qvp_phase4k_resolve_path(figure_dir, must_work = TRUE)
  audit_dir <- app_joint_qvp_phase4k_resolve_path(audit_dir, must_work = FALSE)
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

  freeze_manifest <- app_joint_qvp_phase4_manifest_with_hashes(freeze_dir)
  freeze_manifest_ok <- nrow(freeze_manifest) > 0L && all(freeze_manifest$hash_verified)
  asset_manifest_path <- file.path(table_dir, "joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv")
  if (!file.exists(asset_manifest_path)) stop("Missing Phase 4k article asset manifest.", call. = FALSE)
  asset_manifest <- app_read_csv(asset_manifest_path)
  app_check_required_columns(asset_manifest, c("label", "artifact_type", "path", "sha256"), "Phase 4k article asset manifest")
  asset_abs <- vapply(asset_manifest$path, app_joint_qvp_phase4k_resolve_path, character(1L), must_work = FALSE)
  asset_verification <- asset_manifest
  asset_verification$absolute_path <- asset_abs
  asset_verification$file_exists <- file.exists(asset_abs)
  asset_verification$observed_sha256 <- NA_character_
  asset_verification$observed_sha256[asset_verification$file_exists] <- vapply(asset_abs[asset_verification$file_exists], app_sha256_file, character(1L))
  asset_verification$hash_verified <- asset_verification$file_exists & asset_verification$observed_sha256 == asset_verification$sha256

  decision <- app_read_csv(file.path(freeze_dir, "freeze_decision_summary.csv"))
  source_verification <- app_read_csv(file.path(freeze_dir, "freeze_source_manifest_verification.csv"))
  large_registry <- app_read_csv(file.path(freeze_dir, "freeze_large_file_registry.csv"))
  large_abs <- vapply(large_registry$source_path, app_joint_qvp_phase4k_resolve_path, character(1L), must_work = FALSE)
  large_registry$source_file_exists <- file.exists(large_abs)
  large_registry$observed_source_sha256 <- NA_character_
  large_registry$observed_source_sha256[large_registry$source_file_exists] <- vapply(large_abs[large_registry$source_file_exists], app_sha256_file, character(1L))
  large_registry$source_hash_verified <- large_registry$source_file_exists & large_registry$observed_source_sha256 == large_registry$source_sha256

  freeze_files <- list.files(freeze_dir, pattern = "\\.(csv|md)$", full.names = TRUE, recursive = FALSE)
  freeze_text <- paste(unlist(lapply(freeze_files, readLines, warn = FALSE), use.names = FALSE), collapse = "\n")
  stale_label_found <- grepl("smoke|pilot|calibration_pilot", freeze_text, ignore.case = TRUE)
  selected_arm_value <- as.character(decision$selected_arm_id[[1L]])
  selected_tau0_value <- as.numeric(decision$selected_tau0[[1L]])
  expected_selected_arm <- as.character(expected_selected_arm[[1L]])
  expected_selected_tau0 <- as.numeric(expected_selected_tau0[[1L]])
  selected_arm_ok <- nrow(decision) == 1L &&
    nzchar(selected_arm_value) &&
    (allow_selected_arm_override || !nzchar(expected_selected_arm) || identical(selected_arm_value, expected_selected_arm))
  selected_tau0_ok <- nrow(decision) == 1L &&
    is.finite(selected_tau0_value) &&
    (allow_selected_arm_override || !is.finite(expected_selected_tau0) || abs(selected_tau0_value - expected_selected_tau0) < 1.0e-12)
  selected_consistent <- selected_arm_ok && selected_tau0_ok
  table_rows_ok <- sum(asset_verification$artifact_type == "table" & asset_verification$file_exists) >= 7L
  figure_rows_ok <- sum(asset_verification$artifact_type == "figure" & asset_verification$file_exists) >= 5L
  hard_fail <- !freeze_manifest_ok ||
    !all(asset_verification$hash_verified) ||
    !all(app_as_bool_vec(source_verification$all_hashes_verified)) ||
    !all(large_registry$source_hash_verified) ||
    stale_label_found ||
    !selected_consistent ||
    !table_rows_ok ||
    !figure_rows_ok
  review <- !hard_fail && as.numeric(decision$selected_raw_crossing_pairs[[1L]]) > 0
  audit <- data.frame(
    scope = "phase4k_article_asset_audit",
    freeze_dir = app_prefer_repo_relative_path(freeze_dir),
    table_dir = app_prefer_repo_relative_path(table_dir),
    figure_dir = app_prefer_repo_relative_path(figure_dir),
    freeze_manifest_status = if (freeze_manifest_ok) "pass" else "fail",
    asset_manifest_status = if (all(asset_verification$hash_verified)) "pass" else "fail",
    source_reference_status = if (all(large_registry$source_hash_verified)) "pass" else "fail",
    label_status = if (stale_label_found) "fail" else "pass",
    selected_arm_status = if (selected_consistent) "pass" else "fail",
    table_asset_status = if (table_rows_ok) "pass" else "fail",
    figure_asset_status = if (figure_rows_ok) "pass" else "fail",
    raw_crossing_status = if (as.numeric(decision$selected_raw_crossing_pairs[[1L]]) > 0) "review" else "pass",
    audit_gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    note = app_joint_qvp_ts_assessment_note(c(
      if (!freeze_manifest_ok) "freeze manifest verification failed",
      if (!all(asset_verification$hash_verified)) "article asset hash verification failed",
      if (!all(large_registry$source_hash_verified)) "large source reference hash verification failed",
      if (stale_label_found) "stale smoke/pilot label found",
      if (!selected_consistent) "selected arm/tau0 mismatch",
      if (!table_rows_ok) "missing table assets",
      if (!figure_rows_ok) "missing figure assets",
      if (review) "raw crossings remain diagnostic review evidence"
    )),
    stringsAsFactors = FALSE
  )
  checklist <- data.frame(
    item = c(
      "Freeze manifest verified",
      "Article asset manifest verified",
      "Large source references verified",
      sprintf("Selected arm matches expected %s", if (nzchar(expected_selected_arm)) expected_selected_arm else "nonempty value"),
      sprintf("Selected tau0 matches expected %s", if (is.finite(expected_selected_tau0)) as.character(expected_selected_tau0) else "finite value"),
      "Contract crossings are zero",
      "Raw crossings are disclosed as review evidence",
      "Tables are generated from freeze artifacts",
      "Figures are generated from freeze artifacts",
      "Manuscript can consume Phase 4k assets"
    ),
    status = c(
      if (freeze_manifest_ok) "pass" else "fail",
      if (all(asset_verification$hash_verified)) "pass" else "fail",
      if (all(large_registry$source_hash_verified)) "pass" else "fail",
      if (selected_arm_ok) "pass" else "fail",
      if (selected_tau0_ok) "pass" else "fail",
      if (as.numeric(decision$selected_contract_crossing_pairs[[1L]]) == 0) "pass" else "fail",
      if (as.numeric(decision$selected_raw_crossing_pairs[[1L]]) > 0) "review" else "pass",
      if (table_rows_ok) "pass" else "fail",
      if (figure_rows_ok) "pass" else "fail",
      if (hard_fail) "blocked" else "ready"
    ),
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(audit_dir, "README.md")
  writeLines(c(
    "# Joint-QVP Synthetic DGP Phase 4k Article Asset Audit",
    "",
    sprintf("- Audit gate: %s", audit$audit_gate_status[[1L]]),
    sprintf("- Freeze directory: %s", app_prefer_repo_relative_path(freeze_dir)),
    sprintf("- Table directory: %s", app_prefer_repo_relative_path(table_dir)),
    sprintf("- Figure directory: %s", app_prefer_repo_relative_path(figure_dir)),
    "",
    "Raw crossings remain review evidence when present; contract crossings remain the hard implementation gate."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    phase4k_article_asset_audit = app_joint_qvp_write_csv(audit, file.path(audit_dir, "phase4k_article_asset_audit.csv")),
    phase4k_article_asset_manifest_verification = app_joint_qvp_write_csv(asset_verification, file.path(audit_dir, "phase4k_article_asset_manifest_verification.csv")),
    phase4k_large_source_reference_verification = app_joint_qvp_write_csv(large_registry, file.path(audit_dir, "phase4k_large_source_reference_verification.csv")),
    phase4k_manuscript_integration_checklist = app_joint_qvp_write_csv(checklist, file.path(audit_dir, "phase4k_manuscript_integration_checklist.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(audit_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_qvp_phase4k_manifest_from_paths(paths, audit_dir)
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(audit_dir, "artifact_manifest.csv"))
  list(
    audit_dir = audit_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    audit = audit,
    checklist = checklist
  )
}

app_joint_qvp_qhat_truth_summary <- function(fixture, qhat, fit_label, case_id) {
  qhat <- as.matrix(qhat)
  if (!identical(dim(qhat), dim(fixture$true_q))) {
    stop("qhat must have the same dimensions as fixture$true_q.", call. = FALSE)
  }
  rows <- lapply(seq_along(fixture$tau), function(k) {
    err <- qhat[, k] - fixture$true_q[, k]
    data.frame(
      case_id = case_id,
      fit = fit_label,
      quantile_index = k,
      tau = fixture$tau[[k]],
      rmse_to_truth = sqrt(mean(err^2)),
      mae_to_truth = mean(abs(err)),
      max_abs_error_to_truth = max(abs(err)),
      mean_error_to_truth = mean(err),
      empirical_hit_rate = mean(fixture$y <= qhat[, k]),
      hit_rate_minus_tau = mean(fixture$y <= qhat[, k]) - fixture$tau[[k]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_qhat_truth_distance <- function(fixture, qhat) {
  app_joint_qvp_l2_distance(qhat, fixture$true_q) /
    (sqrt(length(fixture$true_q)) * (1 + sqrt(mean(fixture$true_q^2))))
}

app_joint_qvp_check_loss <- function(residual, tau) {
  residual <- as.numeric(residual)
  tau <- as.numeric(tau)[[1L]]
  if (!is.finite(tau) || tau <= 0 || tau >= 1) {
    stop("tau must be in (0, 1).", call. = FALSE)
  }
  sum(residual * (tau - as.numeric(residual < 0)))
}

app_joint_qvp_fit_check_loss_quantile <- function(
  y,
  Z,
  tau,
  truth_theta = NULL,
  maxit = 8000L,
  reltol = 1.0e-12
) {
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- as.numeric(tau)[[1L]]
  if (length(y) != nrow(Z)) stop("length(y) must match nrow(Z).", call. = FALSE)
  X <- cbind(intercept = 1, Z)
  p <- ncol(X)
  ols_start <- tryCatch(as.numeric(stats::lm.fit(X, y)$coefficients), error = function(e) rep(NA_real_, p))
  if (length(ols_start) != p || any(!is.finite(ols_start))) {
    ols_start <- rep(0, p)
    ols_start[[1L]] <- mean(y)
  }
  quantile_start <- rep(0, p)
  quantile_start[[1L]] <- as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8))
  starts <- list(ols_start, quantile_start)
  if (!is.null(truth_theta)) {
    truth_theta <- as.numeric(truth_theta)
    if (length(truth_theta) != p || any(!is.finite(truth_theta))) {
      stop("truth_theta must be finite and have length ncol(Z) + 1.", call. = FALSE)
    }
    starts <- c(starts, list(truth_theta))
  }
  objective <- function(theta) {
    app_joint_qvp_check_loss(y - as.numeric(X %*% theta), tau)
  }
  fits <- lapply(starts, function(start) {
    stats::optim(
      par = start,
      fn = objective,
      method = "Nelder-Mead",
      control = list(maxit = as.integer(maxit), reltol = reltol)
    )
  })
  values <- vapply(fits, `[[`, numeric(1L), "value")
  best <- fits[[which.min(values)]]
  theta <- as.numeric(best$par)
  qhat <- as.numeric(X %*% theta)
  list(
    theta = theta,
    alpha = theta[[1L]],
    beta = theta[-1L],
    qhat = qhat,
    objective = as.numeric(best$value),
    convergence = as.integer(best$convergence),
    hit_rate = mean(y <= qhat),
    sigma_hat = as.numeric(best$value) / length(y)
  )
}

app_joint_qvp_fit_check_loss_baseline <- function(fixture) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  theta <- matrix(NA_real_, nrow = p + 1L, ncol = K)
  qhat <- matrix(NA_real_, nrow = length(fixture$y), ncol = K)
  rows <- vector("list", K)
  for (k in seq_len(K)) {
    truth_theta <- c(fixture$alpha[[k]], fixture$beta[, k])
    fit <- app_joint_qvp_fit_check_loss_quantile(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau[[k]],
      truth_theta = truth_theta
    )
    theta[, k] <- fit$theta
    qhat[, k] <- fit$qhat
    rows[[k]] <- data.frame(
      quantile_index = k,
      tau = fixture$tau[[k]],
      check_loss = fit$objective,
      convergence = fit$convergence,
      empirical_hit_rate = fit$hit_rate,
      sigma_hat = fit$sigma_hat,
      stringsAsFactors = FALSE
    )
  }
  colnames(theta) <- paste0("tau_", fixture$tau)
  colnames(qhat) <- colnames(fixture$true_q)
  list(
    alpha_mean = theta[1L, ],
    beta_mean = as.numeric(theta[-1L, , drop = FALSE]),
    theta = theta,
    qhat_mean = qhat,
    summary = do.call(rbind, rows),
    tau = fixture$tau
  )
}

app_joint_qvp_readout_truth_summary <- function(fixture, fit, fit_label, case_id) {
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  beta <- app_joint_qvp_beta_matrix(fit$beta_mean, K, p)
  truth <- app_joint_qvp_ts_readout_rows(fixture, case_id, fit_label = "truth")
  fitted <- app_joint_qvp_ts_readout_rows(fixture, case_id, fit_label = fit_label, alpha = fit$alpha_mean, beta = beta)
  merged <- merge(
    truth,
    fitted,
    by = c("case_id", "parameter", "feature", "quantile_index", "tau"),
    suffixes = c("_truth", "_fit"),
    sort = FALSE
  )
  data.frame(
    case_id = merged$case_id,
    fit = fit_label,
    parameter = merged$parameter,
    feature = merged$feature,
    quantile_index = merged$quantile_index,
    tau = merged$tau,
    truth_value = merged$value_truth,
    fit_value = merged$value_fit,
    error = merged$value_fit - merged$value_truth,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_plot_palette <- function(K) {
  rep(c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#56B4E9"), length.out = K)
}

app_joint_qvp_png <- function(path, width = 1300, height = 900, res = 140) {
  grDevices::png(path, width = width, height = height, res = res, type = "cairo")
}

app_joint_qvp_plot_ts_fit_overlay <- function(fixture, vb_fit, pooled_mcmc, path, title) {
  K <- length(fixture$tau)
  x <- seq_along(fixture$y)
  metrics <- rbind(
    app_joint_qvp_qhat_truth_summary(fixture, fixture$true_q, "truth", "plot"),
    app_joint_qvp_qhat_truth_summary(fixture, vb_fit$qhat_mean, "VB", "plot"),
    app_joint_qvp_qhat_truth_summary(fixture, pooled_mcmc$qhat_mean, "pooled MCMC", "plot")
  )
  tau_labels <- paste0("tau = ", formatC(fixture$tau, format = "f", digits = 2))
  overview_range <- range(c(fixture$y, fixture$true_q), finite = TRUE)
  overview_pad <- 0.06 * diff(overview_range)
  if (!is.finite(overview_pad) || overview_pad <= 0) overview_pad <- 1
  app_joint_qvp_png(path, width = 2200, height = 1700, res = 180)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)

  layout_ids <- c(1L, 1L, seq_len(K) + 1L, K + 2L)
  if (length(layout_ids) %% 2L) layout_ids <- c(layout_ids, 0L)
  layout_matrix <- matrix(layout_ids, ncol = 2L, byrow = TRUE)
  graphics::layout(layout_matrix, heights = c(1.15, rep(1, nrow(layout_matrix) - 1L)))
  graphics::par(oma = c(0, 0, 2.8, 0), mar = c(4.1, 4.4, 2.4, 1.1))

  tau_order <- order(fixture$tau)
  low_k <- tau_order[[1L]]
  high_k <- tau_order[[length(tau_order)]]
  mid_k <- which.min(abs(fixture$tau - stats::median(fixture$tau)))
  truth_cols <- app_joint_qvp_plot_palette(K)

  graphics::plot(x, fixture$y, type = "n",
    ylim = overview_range + c(-overview_pad, overview_pad),
    xlab = "time index", ylab = "response / true conditional quantile",
    main = "Truth and observed series")
  graphics::grid(col = "grey88")
  if (K >= 2L) {
    graphics::polygon(
      c(x, rev(x)),
      c(fixture$true_q[, low_k], rev(fixture$true_q[, high_k])),
      border = NA,
      col = grDevices::adjustcolor("#8DD3C7", alpha.f = 0.28)
    )
  }
  graphics::points(x, fixture$y, pch = 16, cex = 0.55, col = grDevices::adjustcolor("grey20", alpha.f = 0.78))
  for (k in seq_len(K)) {
    lwd <- if (k == mid_k) 3 else 2
    graphics::lines(x, fixture$true_q[, k], col = truth_cols[[k]], lwd = lwd)
  }
  graphics::legend("topleft",
    legend = c("observed y", "true central band", tau_labels),
    col = c("grey20", "#8DD3C7", truth_cols),
    pch = c(16, NA, NA, NA),
    lty = c(NA, 1, rep(1, K)),
    lwd = c(NA, 8, rep(2.5, K)),
    bty = "n",
    cex = 0.82
  )

  fit_cols <- c(truth = "#222222", VB = "#0072B2", "pooled MCMC" = "#D55E00")
  fit_lty <- c(truth = 1, VB = 1, "pooled MCMC" = 2)
  for (k in seq_len(K)) {
    y_range <- range(c(fixture$y, fixture$true_q[, k], vb_fit$qhat_mean[, k], pooled_mcmc$qhat_mean[, k]), finite = TRUE)
    y_pad <- 0.06 * diff(y_range)
    if (!is.finite(y_pad) || y_pad <= 0) y_pad <- 1
    graphics::plot(x, fixture$y, type = "n",
      ylim = y_range + c(-y_pad, y_pad),
      xlab = "time index", ylab = "response / fitted quantile",
      main = tau_labels[[k]])
    graphics::grid(col = "grey88")
    graphics::points(x, fixture$y, pch = 16, cex = 0.38, col = grDevices::adjustcolor("grey35", alpha.f = 0.42))
    graphics::lines(x, fixture$true_q[, k], col = fit_cols[["truth"]], lwd = 2.8, lty = fit_lty[["truth"]])
    graphics::lines(x, vb_fit$qhat_mean[, k], col = fit_cols[["VB"]], lwd = 2.3, lty = fit_lty[["VB"]])
    graphics::lines(x, pooled_mcmc$qhat_mean[, k], col = fit_cols[["pooled MCMC"]], lwd = 2.3, lty = fit_lty[["pooled MCMC"]])
    if (k == 1L) {
      graphics::legend("topright",
        legend = c("truth", "VB", "pooled MCMC"),
        col = fit_cols,
        lwd = c(2.8, 2.3, 2.3),
        lty = fit_lty,
        bty = "n",
        cex = 0.82
      )
    }
    vb_row <- metrics[metrics$fit == "VB" & metrics$quantile_index == k, , drop = FALSE]
    mc_row <- metrics[metrics$fit == "pooled MCMC" & metrics$quantile_index == k, , drop = FALSE]
    usr <- graphics::par("usr")
    graphics::text(usr[[1L]] + 0.02 * diff(usr[1:2]), usr[[4L]] - 0.09 * diff(usr[3:4]),
      labels = sprintf("VB RMSE %.2f, bias %.2f, hit %.2f", vb_row$rmse_to_truth, vb_row$mean_error_to_truth, vb_row$empirical_hit_rate),
      adj = c(0, 1), cex = 0.78, col = fit_cols[["VB"]])
    graphics::text(usr[[1L]] + 0.02 * diff(usr[1:2]), usr[[4L]] - 0.17 * diff(usr[3:4]),
      labels = sprintf("MCMC RMSE %.2f, bias %.2f, hit %.2f", mc_row$rmse_to_truth, mc_row$mean_error_to_truth, mc_row$empirical_hit_rate),
      adj = c(0, 1), cex = 0.78, col = fit_cols[["pooled MCMC"]])
  }

  graphics::plot.new()
  graphics::title("Numerical audit")
  truth_width <- if (K >= 2L) fixture$true_q[, high_k] - fixture$true_q[, low_k] else rep(NA_real_, length(x))
  graphics::text(0, 0.92, "Saved metrics for each quantile path", adj = 0, font = 2, cex = 0.95)
  graphics::text(0, 0.84,
    sprintf("Truth band mean width %.3f; max width %.3f; observed y sd %.3f",
      mean(truth_width, na.rm = TRUE), max(truth_width, na.rm = TRUE), stats::sd(fixture$y)),
    adj = 0, cex = 0.68, col = "grey25")
  header <- sprintf("%-8s %-10s %8s %8s %8s", "tau", "fit", "RMSE", "bias", "hit")
  graphics::text(0, 0.76, header, adj = 0, family = "mono", cex = 0.72)
  yy <- 0.68
  for (k in seq_len(K)) {
    for (fit_label in c("truth", "VB", "pooled MCMC")) {
      row <- metrics[metrics$fit == fit_label & metrics$quantile_index == k, , drop = FALSE]
      fit_short <- if (identical(fit_label, "pooled MCMC")) "MCMC" else fit_label
      line <- sprintf("%-8.2f %-10s %8.3f %8.3f %8.3f",
        row$tau, fit_short, row$rmse_to_truth, row$mean_error_to_truth, row$empirical_hit_rate)
      graphics::text(0, yy, line, adj = 0, family = "mono", cex = 0.68,
        col = fit_cols[[fit_label]])
      yy <- yy - 0.056
    }
    yy <- yy - 0.018
  }
  graphics::mtext(paste(title, "truth, VB, and VB-initialized MCMC"), outer = TRUE, side = 3, line = 1, font = 2, cex = 1.05)
  graphics::mtext("Per-tau panels use their own y-axis so tail bias is visible without hiding the true data scale.", outer = TRUE, side = 3, line = -0.4, cex = 0.78, col = "grey30")
  graphics::layout(1L)
  invisible(path)
}

app_joint_qvp_plot_ts_error_hit <- function(fixture, vb_fit, pooled_mcmc, path, title) {
  K <- length(fixture$tau)
  cols <- app_joint_qvp_plot_palette(K)
  x <- seq_along(fixture$y)
  app_joint_qvp_png(path, width = 1400, height = 950)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(2, 1), mar = c(4, 4, 3, 1))
  err_range <- range(c(vb_fit$qhat_mean - fixture$true_q, pooled_mcmc$qhat_mean - fixture$true_q), finite = TRUE)
  graphics::plot(x, vb_fit$qhat_mean[, 1L] - fixture$true_q[, 1L],
    type = "n", ylim = err_range, xlab = "time index", ylab = "fit minus truth",
    main = paste(title, "quantile-path errors"))
  for (k in seq_len(K)) {
    graphics::lines(x, vb_fit$qhat_mean[, k] - fixture$true_q[, k], col = cols[[k]], lwd = 2)
    graphics::lines(x, pooled_mcmc$qhat_mean[, k] - fixture$true_q[, k], col = cols[[k]], lwd = 2, lty = 2)
  }
  graphics::abline(h = 0, col = "grey45", lty = 3)
  graphics::grid(col = "grey85")
  graphics::legend("topright", legend = paste0("tau=", fixture$tau), col = cols, lwd = 2, bty = "n", cex = 0.85)
  hits <- rbind(
    data.frame(fit = "truth", tau = fixture$tau, hit = vapply(seq_len(K), function(k) mean(fixture$y <= fixture$true_q[, k]), numeric(1L))),
    data.frame(fit = "VB", tau = fixture$tau, hit = vapply(seq_len(K), function(k) mean(fixture$y <= vb_fit$qhat_mean[, k]), numeric(1L))),
    data.frame(fit = "MCMC", tau = fixture$tau, hit = vapply(seq_len(K), function(k) mean(fixture$y <= pooled_mcmc$qhat_mean[, k]), numeric(1L)))
  )
  offsets <- c(truth = -0.018, VB = 0, MCMC = 0.018)
  graphics::plot(fixture$tau, fixture$tau, type = "l", lwd = 2, col = "grey40",
    xlim = range(fixture$tau) + c(-0.06, 0.06), ylim = c(0, 1),
    xlab = "nominal tau", ylab = "empirical hit rate",
    main = "Empirical hit rates")
  for (fit_label in unique(hits$fit)) {
    block <- hits[hits$fit == fit_label, , drop = FALSE]
    graphics::points(block$tau + offsets[[fit_label]], block$hit,
      pch = if (fit_label == "truth") 16 else if (fit_label == "VB") 17 else 15,
      col = if (fit_label == "truth") "grey25" else if (fit_label == "VB") "#0072B2" else "#D55E00",
      cex = 1.2)
  }
  graphics::grid(col = "grey85")
  graphics::legend("topleft", legend = c("nominal", "truth", "VB", "MCMC"),
    col = c("grey40", "grey25", "#0072B2", "#D55E00"),
    lty = c(1, NA, NA, NA), pch = c(NA, 16, 17, 15), bty = "n", cex = 0.85)
  invisible(path)
}

app_joint_qvp_plot_ts_elbo <- function(vb_fit, path, title) {
  app_joint_qvp_png(path, width = 1200, height = 900)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(2, 1), mar = c(4, 4, 3, 1))
  graphics::plot(vb_fit$trace$iter, vb_fit$trace$partial_elbo, type = "l", lwd = 2,
    col = "#0072B2", xlab = "VB iteration", ylab = "accounted partial ELBO",
    main = paste(title, "VB objective"))
  graphics::grid(col = "grey85")
  graphics::plot(vb_fit$trace$iter, pmax(vb_fit$trace$max_beta_change, .Machine$double.eps),
    type = "l", log = "y", lwd = 2, col = "#D55E00",
    xlab = "VB iteration", ylab = "max beta change",
    main = "Coordinate-change diagnostic")
  graphics::abline(h = 1.0e-4, lty = 2, col = "grey40")
  graphics::grid(col = "grey85")
  invisible(path)
}

app_joint_qvp_plot_ts_mcmc_traces <- function(mcmc_fits, tau, path, title) {
  K <- length(tau)
  cols <- app_joint_qvp_plot_palette(K)
  app_joint_qvp_png(path, width = 1300, height = 1100)
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(3, 1), mar = c(4, 4, 3, 1))
  draw_x <- seq_len(nrow(mcmc_fits[[1L]]$sigma_draws))
  for (block_name in c("sigma_draws", "alpha_draws")) {
    y_range <- range(unlist(lapply(mcmc_fits, `[[`, block_name)), finite = TRUE)
    ylab <- if (identical(block_name, "sigma_draws")) "sigma" else "alpha"
    graphics::plot(draw_x, mcmc_fits[[1L]][[block_name]][, 1L], type = "n",
      ylim = y_range, xlab = "kept MCMC draw", ylab = ylab,
      main = paste(title, ylab, "traces"))
    for (chain_id in seq_along(mcmc_fits)) {
      for (k in seq_len(K)) {
        graphics::lines(draw_x, mcmc_fits[[chain_id]][[block_name]][, k],
          col = cols[[k]], lty = chain_id, lwd = 1.5)
      }
    }
    graphics::grid(col = "grey85")
  }
  beta_norms <- lapply(mcmc_fits, function(fit) sqrt(rowSums(fit$beta_draws^2)))
  graphics::plot(draw_x, beta_norms[[1L]], type = "n",
    ylim = range(unlist(beta_norms), finite = TRUE), xlab = "kept MCMC draw",
    ylab = "||beta||2", main = "Readout-norm traces")
  for (chain_id in seq_along(beta_norms)) {
    graphics::lines(draw_x, beta_norms[[chain_id]], col = "#009E73", lty = chain_id, lwd = 1.5)
  }
  graphics::grid(col = "grey85")
  invisible(path)
}

app_joint_qvp_run_ts_toy_fit_validation <- function(
  out_dir,
  Tn = 60L,
  tau = c(0.1, 0.5, 0.9),
  seed = 20260701L,
  df = 5,
  innovation = "student_t",
  al_tau = 0.5,
  period = 24L,
  kappa = 1,
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 180L,
  rhs_vb_inner = 5L,
  n_chains = 2L,
  mcmc_n_iter = 120L,
  mcmc_burn = 60L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  sigma_upper_multiplier = 50,
  make_figures = TRUE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fixture <- app_joint_qvp_simulate_ts_toy_synthetic(
    Tn = Tn,
    tau = tau,
    seed = seed,
    df = df,
    innovation = innovation,
    al_tau = al_tau,
    period = period
  )
  case_id <- sprintf("ts_toy_%s_seed%s_K%s", innovation, seed, length(fixture$tau))
  vb_fit <- app_joint_qvp_fit_al_vb_tiny(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    max_iter = vb_max_iter,
    tol = 1.0e-4,
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    alpha_prior_sd = alpha_prior_sd,
    rhs_vb_inner = rhs_vb_inner
  )
  sigma_upper_bound <- max(1, sigma_upper_multiplier * max(vb_fit$sigma_mean))
  fits <- vector("list", n_chains)
  draw_rows <- list()
  crossing_rows <- list()
  for (chain_id in seq_len(n_chains)) {
    chain_seed <- seed + mcmc_seed_offset + (chain_id - 1L) * chain_seed_stride
    fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_n_iter,
      burn = mcmc_burn,
      thin = mcmc_thin,
      seed = chain_seed,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      init = vb_fit,
      max_dense_dim = 100L,
      sigma_bounds = c(1.0e-8, sigma_upper_bound)
    )
    draw_rows[[length(draw_rows) + 1L]] <- cbind(
      data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
      app_joint_qvp_mcmc_draw_summary(fits[[chain_id]], case_id, "ts_toy", fixture$dynamic, sigma_bounds = c(1.0e-8, sigma_upper_bound))
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, fit = sprintf("chain_%s", chain_id), chain_id = chain_id, stringsAsFactors = FALSE),
      fits[[chain_id]]$crossing_diagnostics
    )
  }
  pooled <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
  truth_fit_summary <- rbind(
    app_joint_qvp_qhat_truth_summary(fixture, fixture$true_q, "truth", case_id),
    app_joint_qvp_qhat_truth_summary(fixture, vb_fit$qhat_mean, "vb", case_id),
    app_joint_qvp_qhat_truth_summary(fixture, pooled$qhat_mean, "pooled_mcmc", case_id)
  )
  readout_truth <- rbind(
    app_joint_qvp_readout_truth_summary(fixture, vb_fit, "vb", case_id),
    app_joint_qvp_readout_truth_summary(fixture, pooled, "pooled_mcmc", case_id)
  )
  vb_mcmc_distance <- app_joint_qvp_vb_mcmc_distance_summary(
    vb_fit = vb_fit,
    mcmc_fit = pooled,
    case_id = case_id,
    stress_case = "ts_toy",
    scenario = fixture$dynamic,
    Tn = length(fixture$y),
    p = ncol(fixture$Z),
    K = length(fixture$tau)
  )
  vb_crossing <- cbind(data.frame(case_id = case_id, fit = "vb", chain_id = NA_integer_, stringsAsFactors = FALSE), vb_fit$crossing_diagnostics)
  pooled_crossing <- cbind(data.frame(case_id = case_id, fit = "pooled_mcmc", chain_id = NA_integer_, stringsAsFactors = FALSE), pooled$crossing_diagnostics)
  crossing_summary <- do.call(rbind, c(crossing_rows, list(vb_crossing, pooled_crossing)))
  draw_summary <- do.call(rbind, draw_rows)
  fit_summary <- data.frame(
    case_id = case_id,
    dynamic = fixture$dynamic,
    likelihood = fixture$likelihood,
    seed = seed,
    Tn = length(fixture$y),
    p = ncol(fixture$Z),
    K = length(fixture$tau),
    tau = paste(fixture$tau, collapse = ","),
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    alpha_prior_sd = alpha_prior_sd,
    vb_status = vb_fit$manifest$status[[1L]],
    vb_converged = isTRUE(vb_fit$converged),
    vb_n_iter = nrow(vb_fit$trace),
    objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
    n_chains = n_chains,
    mcmc_n_keep_total = nrow(pooled$beta_draws),
    sigma_upper_bound = sigma_upper_bound,
    vb_truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, vb_fit$qhat_mean),
    pooled_mcmc_truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, pooled$qhat_mean),
    vb_mcmc_max_normalized_distance = vb_mcmc_distance$max_normalized_distance[[1L]],
    max_abs_vb_hit_rate_error = max(abs(truth_fit_summary$hit_rate_minus_tau[truth_fit_summary$fit == "vb"])),
    max_abs_pooled_mcmc_hit_rate_error = max(abs(truth_fit_summary$hit_rate_minus_tau[truth_fit_summary$fit == "pooled_mcmc"])),
    total_vb_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
    total_pooled_mcmc_crossing_pairs = sum(pooled$crossing_diagnostics$n_crossing_pairs),
    all_chain_draws_finite = all(draw_summary$all_finite),
    stringsAsFactors = FALSE
  )
  observed <- app_joint_qvp_ts_observed_rows(fixture, case_id)
  design <- app_joint_qvp_ts_design_rows(fixture, case_id)
  true_quantiles <- data.frame(case_id = case_id, time_index = seq_len(nrow(fixture$true_q)), fixture$true_q, check.names = FALSE)
  figure_paths <- c()
  if (isTRUE(make_figures)) {
    figure_paths <- c(
      fit_overlay = file.path(out_dir, paste0(case_id, "_fit_overlay.png")),
      error_hit = file.path(out_dir, paste0(case_id, "_error_hit.png")),
      elbo_trace = file.path(out_dir, paste0(case_id, "_elbo_trace.png")),
      parameter_traces = file.path(out_dir, paste0(case_id, "_parameter_traces.png"))
    )
    title <- sprintf("TS toy %s", fixture$likelihood)
    app_joint_qvp_plot_ts_fit_overlay(fixture, vb_fit, pooled, figure_paths[["fit_overlay"]], title)
    app_joint_qvp_plot_ts_error_hit(fixture, vb_fit, pooled, figure_paths[["error_hit"]], title)
    app_joint_qvp_plot_ts_elbo(vb_fit, figure_paths[["elbo_trace"]], title)
    app_joint_qvp_plot_ts_mcmc_traces(fits, fixture$tau, figure_paths[["parameter_traces"]], title)
  }
  figure_manifest <- if (length(figure_paths)) {
    data.frame(
      label = names(figure_paths),
      relative_path = basename(figure_paths),
      size_bytes = as.numeric(file.info(figure_paths)$size),
      sha256 = vapply(figure_paths, app_sha256_file, character(1L)),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(label = character(), relative_path = character(), size_bytes = numeric(), sha256 = character())
  }
  final_elbo_terms <- vb_fit$elbo_terms[vb_fit$elbo_terms$iter == max(vb_fit$elbo_terms$iter), , drop = FALSE]
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      case_id = case_id,
      seed = seed,
      Tn = length(fixture$y),
      tau = paste(fixture$tau, collapse = ","),
      likelihood = fixture$likelihood,
      dynamic = fixture$dynamic,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      vb_max_iter = vb_max_iter,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      stringsAsFactors = FALSE
    ), file.path(out_dir, "run_config.csv")),
    observed_series = app_joint_qvp_write_csv(observed, file.path(out_dir, "observed_series.csv")),
    design_matrix = app_joint_qvp_write_csv(design, file.path(out_dir, "design_matrix.csv")),
    true_quantiles = app_joint_qvp_write_csv(true_quantiles, file.path(out_dir, "true_quantiles.csv")),
    fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
    truth_fit_summary = app_joint_qvp_write_csv(truth_fit_summary, file.path(out_dir, "truth_fit_summary.csv")),
    readout_truth_summary = app_joint_qvp_write_csv(readout_truth, file.path(out_dir, "readout_truth_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(vb_fit$objective_diagnostics, file.path(out_dir, "objective_diagnostics.csv")),
    elbo_terms = app_joint_qvp_write_csv(final_elbo_terms, file.path(out_dir, "elbo_terms.csv")),
    figure_manifest = app_joint_qvp_write_csv(figure_manifest, file.path(out_dir, "figure_manifest.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  paths <- c(paths, figure_paths)
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_ts_hit_rate_threshold <- function(tau, Tn, floor = 0.10, multiplier = 2.5) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  max(floor, multiplier * max(sqrt(tau * (1 - tau) / as.numeric(Tn))))
}

app_joint_qvp_ts_assessment_note <- function(reasons) {
  reasons <- reasons[nzchar(reasons)]
  if (!length(reasons)) "all provisional suite gates passed" else paste(reasons, collapse = "; ")
}

app_joint_qvp_normalize_vb_max_iter_grid <- function(vb_max_iter, adaptive_vb_max_iter_grid = NULL) {
  vb_max_iter <- as.integer(vb_max_iter)[[1L]]
  if (!is.finite(vb_max_iter) || vb_max_iter <= 0L) stop("vb_max_iter must be a positive integer.", call. = FALSE)
  grid <- if (is.null(adaptive_vb_max_iter_grid)) vb_max_iter else as.integer(adaptive_vb_max_iter_grid)
  grid <- sort(unique(c(vb_max_iter, grid[is.finite(grid) & grid > 0L])))
  if (!length(grid)) stop("adaptive_vb_max_iter_grid must contain positive integers.", call. = FALSE)
  grid
}

app_joint_qvp_fit_al_vb_adaptive <- function(
  y,
  Z,
  tau,
  vb_max_iter,
  adaptive_vb_max_iter_grid = NULL,
  tol = 1.0e-4,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  alpha_min_spacing = 0,
  rhs_vb_inner = 5L
) {
  grid <- app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid)
  audit_rows <- vector("list", length(grid))
  final_fit <- NULL
  for (ii in seq_along(grid)) {
    max_iter <- grid[[ii]]
    fit <- app_joint_qvp_fit_al_vb_tiny(
      y = y,
      Z = Z,
      tau = tau,
      max_iter = max_iter,
      tol = tol,
      kappa = kappa,
      tau0 = tau0,
      zeta2 = zeta2,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = alpha_min_spacing,
      rhs_vb_inner = rhs_vb_inner
    )
    final_fit <- fit
    audit_rows[[ii]] <- data.frame(
      attempt = ii,
      max_iter = max_iter,
      converged = isTRUE(fit$converged),
      status = fit$manifest$status[[1L]],
      n_iter = nrow(fit$trace),
      final_max_beta_change = tail(fit$trace$max_beta_change, 1L),
      objective_status = fit$objective_diagnostics$objective_status[[1L]],
      stringsAsFactors = FALSE
    )
    if (isTRUE(fit$converged)) break
  }
  audit <- app_bind_rows_fill(audit_rows)
  list(
    fit = final_fit,
    audit = audit,
    grid = grid,
    policy = if (length(grid) > 1L) "adaptive_max_iter_grid" else "fixed_max_iter"
  )
}

app_joint_qvp_fit_ts_synthetic_scenario <- function(
  sc,
  out_dir = NULL,
  kappa = 1,
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 180L,
  adaptive_vb_max_iter_grid = NULL,
  rhs_vb_inner = 5L,
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  sigma_upper_multiplier = 50,
  make_figures = FALSE
) {
  if (!is.data.frame(sc) || nrow(sc) != 1L) {
    stop("sc must be a one-row time-series synthetic scenario data frame.", call. = FALSE)
  }
  if (isTRUE(make_figures) && is.null(out_dir)) {
    stop("out_dir is required when make_figures = TRUE.", call. = FALSE)
  }
  if (!is.null(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  fixture <- app_joint_qvp_ts_fixture_from_scenario(sc)
  case_id <- as.character(sc$case_id[[1L]])
  seed <- as.integer(sc$seed[[1L]])
  Tn <- length(fixture$y)
  p <- ncol(fixture$Z)
  K <- length(fixture$tau)
  alpha_prior_mean_label <- if (is.null(alpha_prior_mean)) {
    "none"
  } else {
    paste(as.character(alpha_prior_mean), collapse = ",")
  }

  vb_adaptive <- app_joint_qvp_fit_al_vb_adaptive(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    tol = 1.0e-4,
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    alpha_prior_sd = alpha_prior_sd,
    rhs_vb_inner = rhs_vb_inner
  )
  vb_fit <- vb_adaptive$fit
  vb_convergence_audit <- cbind(
    data.frame(case_id = case_id, dynamic = fixture$dynamic, likelihood = fixture$likelihood, stringsAsFactors = FALSE),
    vb_adaptive$audit
  )
  sigma_upper_bound <- max(1, sigma_upper_multiplier * max(vb_fit$sigma_mean))

  fits <- vector("list", n_chains)
  chain_seeds <- integer(n_chains)
  draw_rows <- list()
  crossing_rows <- list()
  for (chain_id in seq_len(n_chains)) {
    chain_seed <- seed + mcmc_seed_offset + (chain_id - 1L) * chain_seed_stride
    chain_seeds[[chain_id]] <- chain_seed
    fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_n_iter,
      burn = mcmc_burn,
      thin = mcmc_thin,
      seed = chain_seed,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      init = vb_fit,
      max_dense_dim = 100L,
      sigma_bounds = c(1.0e-8, sigma_upper_bound)
    )
    draw_rows[[length(draw_rows) + 1L]] <- cbind(
      data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
      app_joint_qvp_mcmc_draw_summary(
        fits[[chain_id]],
        case_id,
        "ts_suite",
        fixture$dynamic,
        sigma_bounds = c(1.0e-8, sigma_upper_bound)
      )
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, fit = sprintf("chain_%s", chain_id), chain_id = chain_id, stringsAsFactors = FALSE),
      fits[[chain_id]]$crossing_diagnostics
    )
  }

  pooled <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, K, p, fixture$tau)
  truth_fit_summary <- rbind(
    app_joint_qvp_qhat_truth_summary(fixture, fixture$true_q, "truth", case_id),
    app_joint_qvp_qhat_truth_summary(fixture, vb_fit$qhat_mean, "vb", case_id),
    app_joint_qvp_qhat_truth_summary(fixture, pooled$qhat_mean, "pooled_mcmc", case_id)
  )
  readout_truth <- rbind(
    app_joint_qvp_readout_truth_summary(fixture, vb_fit, "vb", case_id),
    app_joint_qvp_readout_truth_summary(fixture, pooled, "pooled_mcmc", case_id)
  )
  vb_mcmc_distance <- app_joint_qvp_vb_mcmc_distance_summary(
    vb_fit = vb_fit,
    mcmc_fit = pooled,
    case_id = case_id,
    stress_case = "ts_suite",
    scenario = fixture$dynamic,
    Tn = Tn,
    p = p,
    K = K
  )
  chain_summary <- app_joint_qvp_chain_to_pooled_summary(
    fits = fits,
    pooled_fit = pooled,
    Z = fixture$Z,
    case_id = case_id,
    stress_case = "ts_suite",
    scenario = fixture$dynamic,
    Tn = Tn,
    p = p,
    K = K
  )
  chain_summary$chain_seed <- chain_seeds[chain_summary$chain_id]

  vb_crossing <- cbind(data.frame(case_id = case_id, fit = "vb", chain_id = NA_integer_, stringsAsFactors = FALSE), vb_fit$crossing_diagnostics)
  pooled_crossing <- cbind(data.frame(case_id = case_id, fit = "pooled_mcmc", chain_id = NA_integer_, stringsAsFactors = FALSE), pooled$crossing_diagnostics)
  crossing_summary <- do.call(rbind, c(crossing_rows, list(vb_crossing, pooled_crossing)))
  draw_summary <- do.call(rbind, draw_rows)
  sigma_draw_rows <- draw_summary[draw_summary$block == "sigma", , drop = FALSE]
  max_sigma_upper_hit <- if (nrow(sigma_draw_rows)) {
    max(sigma_draw_rows$upper_bound_hit_fraction, na.rm = TRUE)
  } else {
    NA_real_
  }
  all_chains_warmstarted <- all(vapply(fits, function(fit) identical(fit$init_source, "provided"), logical(1L)))

  fit_summary <- data.frame(
    case_id = case_id,
    dynamic = fixture$dynamic,
    likelihood = fixture$likelihood,
    seed = seed,
    Tn = Tn,
    p = p,
    K = K,
    tau = paste(fixture$tau, collapse = ","),
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean_label,
    alpha_prior_sd = alpha_prior_sd,
    vb_status = vb_fit$manifest$status[[1L]],
    vb_converged = isTRUE(vb_fit$converged),
    vb_n_iter = nrow(vb_fit$trace),
    vb_initial_max_iter = as.integer(vb_max_iter),
    vb_max_iter_grid = paste(vb_adaptive$grid, collapse = ","),
    vb_max_iter_used = max(vb_convergence_audit$max_iter),
    vb_retry_count = max(vb_convergence_audit$attempt) - 1L,
    vb_convergence_policy = vb_adaptive$policy,
    vb_final_max_beta_change = tail(vb_fit$trace$max_beta_change, 1L),
    objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_n_keep_total = nrow(pooled$beta_draws),
    mcmc_init_source = pooled$init_source,
    all_chains_warmstarted = all_chains_warmstarted,
    sigma_upper_bound = sigma_upper_bound,
    max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
    vb_truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, vb_fit$qhat_mean),
    pooled_mcmc_truth_normalized_qhat_distance = app_joint_qvp_qhat_truth_distance(fixture, pooled$qhat_mean),
    vb_mcmc_max_normalized_distance = vb_mcmc_distance$max_normalized_distance[[1L]],
    max_chain_to_pooled_normalized_distance = max(chain_summary$max_normalized_to_pooled, na.rm = TRUE),
    max_abs_vb_hit_rate_error = max(abs(truth_fit_summary$hit_rate_minus_tau[truth_fit_summary$fit == "vb"])),
    max_abs_pooled_mcmc_hit_rate_error = max(abs(truth_fit_summary$hit_rate_minus_tau[truth_fit_summary$fit == "pooled_mcmc"])),
    total_vb_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
    total_pooled_mcmc_crossing_pairs = sum(pooled$crossing_diagnostics$n_crossing_pairs),
    all_chain_draws_finite = all(draw_summary$all_finite),
    notes = as.character(sc$notes[[1L]]),
    stringsAsFactors = FALSE
  )

  objective_diagnostics <- cbind(
    data.frame(case_id = case_id, dynamic = fixture$dynamic, likelihood = fixture$likelihood, stringsAsFactors = FALSE),
    vb_fit$objective_diagnostics
  )
  final_elbo_terms <- vb_fit$elbo_terms[vb_fit$elbo_terms$iter == max(vb_fit$elbo_terms$iter), , drop = FALSE]
  final_elbo_terms <- cbind(
    data.frame(case_id = case_id, dynamic = fixture$dynamic, likelihood = fixture$likelihood, stringsAsFactors = FALSE),
    final_elbo_terms
  )

  figure_paths <- c()
  if (isTRUE(make_figures)) {
    safe_case_id <- gsub("[^A-Za-z0-9_.-]+", "_", case_id)
    figure_paths <- stats::setNames(
      c(
        file.path(out_dir, paste0(safe_case_id, "_fit_overlay.png")),
        file.path(out_dir, paste0(safe_case_id, "_error_hit.png"))
      ),
      c(paste0(case_id, "_fit_overlay"), paste0(case_id, "_error_hit"))
    )
    title <- sprintf("%s %s", case_id, fixture$likelihood)
    app_joint_qvp_plot_ts_fit_overlay(fixture, vb_fit, pooled, figure_paths[[1L]], title)
    app_joint_qvp_plot_ts_error_hit(fixture, vb_fit, pooled, figure_paths[[2L]], title)
  }
  figure_manifest <- if (length(figure_paths)) {
    data.frame(
      label = names(figure_paths),
      relative_path = basename(figure_paths),
      size_bytes = as.numeric(file.info(figure_paths)$size),
      sha256 = vapply(figure_paths, app_sha256_file, character(1L)),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(label = character(), relative_path = character(), size_bytes = numeric(), sha256 = character())
  }

  list(
    case_id = case_id,
    fixture = fixture,
    vb_fit = vb_fit,
    mcmc_fits = fits,
    pooled_mcmc = pooled,
    fit_summary = fit_summary,
    truth_fit_summary = truth_fit_summary,
    readout_truth_summary = readout_truth,
    vb_mcmc_distance_summary = vb_mcmc_distance,
    chain_summary = chain_summary,
    mcmc_draw_summary = draw_summary,
    crossing_summary = crossing_summary,
    vb_convergence_audit = vb_convergence_audit,
    objective_diagnostics = objective_diagnostics,
    elbo_terms = final_elbo_terms,
    figure_manifest = figure_manifest,
    figure_paths = figure_paths
  )
}

app_joint_qvp_assess_ts_suite_fit_validation <- function(
  fit_summary,
  truth_fit_summary = NULL,
  vb_truth_pass = 1.5,
  pooled_mcmc_truth_pass = 2.0,
  vb_mcmc_pass = 5,
  hit_rate_floor = 0.10,
  hit_rate_multiplier = 2.5
) {
  if (!nrow(fit_summary)) return(data.frame())
  rows <- vector("list", nrow(fit_summary))
  for (ii in seq_len(nrow(fit_summary))) {
    fit <- fit_summary[ii, , drop = FALSE]
    tau <- app_joint_qvp_parse_tau_spec(fit$tau[[1L]])
    hit_threshold_max <- app_joint_qvp_ts_hit_rate_threshold(
      tau,
      fit$Tn[[1L]],
      floor = hit_rate_floor,
      multiplier = hit_rate_multiplier
    )
    if (!is.null(truth_fit_summary) && nrow(truth_fit_summary)) {
      hit_rows <- truth_fit_summary[
        truth_fit_summary$case_id == fit$case_id[[1L]] &
          truth_fit_summary$fit %in% c("vb", "pooled_mcmc"),
        ,
        drop = FALSE
      ]
      hit_allowed <- pmax(
        hit_rate_floor,
        hit_rate_multiplier * sqrt(hit_rows$tau * (1 - hit_rows$tau) / fit$Tn[[1L]])
      )
      hit_abs_error <- abs(hit_rows$hit_rate_minus_tau)
      hit_rate_status <- if (length(hit_abs_error) && all(hit_abs_error <= hit_allowed, na.rm = FALSE)) "pass" else "review"
      max_hit_error <- if (length(hit_abs_error)) max(hit_abs_error, na.rm = TRUE) else NA_real_
      max_hit_allowed <- if (length(hit_allowed)) max(hit_allowed, na.rm = TRUE) else hit_threshold_max
    } else {
      hit_errors <- c(fit$max_abs_vb_hit_rate_error[[1L]], fit$max_abs_pooled_mcmc_hit_rate_error[[1L]])
      hit_rate_status <- if (all(is.finite(hit_errors)) && max(hit_errors) <= hit_threshold_max) "pass" else "review"
      max_hit_error <- max(hit_errors, na.rm = TRUE)
      max_hit_allowed <- hit_threshold_max
    }

    finite_required <- all(is.finite(c(
      fit$vb_truth_normalized_qhat_distance[[1L]],
      fit$pooled_mcmc_truth_normalized_qhat_distance[[1L]],
      fit$vb_mcmc_max_normalized_distance[[1L]],
      fit$max_chain_to_pooled_normalized_distance[[1L]],
      fit$max_abs_vb_hit_rate_error[[1L]],
      fit$max_abs_pooled_mcmc_hit_rate_error[[1L]],
      fit$max_sigma_upper_bound_hit_fraction[[1L]]
    )))
    hard_fail <- !finite_required ||
      !isTRUE(fit$all_chains_warmstarted[[1L]]) ||
      !isTRUE(fit$all_chain_draws_finite[[1L]]) ||
      fit$total_vb_crossing_pairs[[1L]] > 0 ||
      fit$total_pooled_mcmc_crossing_pairs[[1L]] > 0 ||
      fit$max_sigma_upper_bound_hit_fraction[[1L]] > 0
    implementation_status <- if (hard_fail) {
      "fail"
    } else if (!identical(as.character(fit$vb_status[[1L]]), "prototype_success") || !isTRUE(fit$vb_converged[[1L]])) {
      "review"
    } else {
      "pass"
    }
    objective_gate_status <- if (identical(as.character(fit$objective_status[[1L]]), "pass")) "pass" else "review"
    truth_distance_status <- if (
      is.finite(fit$vb_truth_normalized_qhat_distance[[1L]]) &&
        fit$vb_truth_normalized_qhat_distance[[1L]] <= vb_truth_pass &&
        is.finite(fit$pooled_mcmc_truth_normalized_qhat_distance[[1L]]) &&
        fit$pooled_mcmc_truth_normalized_qhat_distance[[1L]] <= pooled_mcmc_truth_pass
    ) {
      "pass"
    } else {
      "review"
    }
    vb_mcmc_status <- if (
      is.finite(fit$vb_mcmc_max_normalized_distance[[1L]]) &&
        fit$vb_mcmc_max_normalized_distance[[1L]] <= vb_mcmc_pass
    ) {
      "pass"
    } else {
      "review"
    }
    gate_status <- if (identical(implementation_status, "fail")) {
      "fail"
    } else if (any(c(implementation_status, objective_gate_status, truth_distance_status, hit_rate_status, vb_mcmc_status) == "review")) {
      "review"
    } else {
      "pass"
    }
    reasons <- c(
      if (!finite_required) "non-finite required fit summary",
      if (!isTRUE(fit$all_chains_warmstarted[[1L]])) "MCMC was not fully VB-initialized",
      if (!isTRUE(fit$all_chain_draws_finite[[1L]])) "non-finite MCMC draws",
      if (fit$total_vb_crossing_pairs[[1L]] > 0 || fit$total_pooled_mcmc_crossing_pairs[[1L]] > 0) "fitted quantile crossings",
      if (fit$max_sigma_upper_bound_hit_fraction[[1L]] > 0) "positive sigma upper-bound hit fraction",
      if (!identical(implementation_status, "pass") && !identical(implementation_status, "fail")) "VB status/convergence review",
      if (!identical(objective_gate_status, "pass")) "accounted objective review",
      if (!identical(truth_distance_status, "pass")) "truth-distance review",
      if (!identical(hit_rate_status, "pass")) "hit-rate review",
      if (!identical(vb_mcmc_status, "pass")) "VB/MCMC agreement review"
    )
    rows[[ii]] <- data.frame(
      case_id = fit$case_id[[1L]],
      dynamic = fit$dynamic[[1L]],
      likelihood = fit$likelihood[[1L]],
      implementation_status = implementation_status,
      objective_gate_status = objective_gate_status,
      truth_distance_status = truth_distance_status,
      hit_rate_status = hit_rate_status,
      vb_mcmc_status = vb_mcmc_status,
      gate_status = gate_status,
      vb_truth_pass_threshold = vb_truth_pass,
      pooled_mcmc_truth_pass_threshold = pooled_mcmc_truth_pass,
      vb_mcmc_pass_threshold = vb_mcmc_pass,
      hit_rate_threshold_max = hit_threshold_max,
      max_hit_rate_error = max_hit_error,
      max_hit_rate_allowed = max_hit_allowed,
      note = app_joint_qvp_ts_assessment_note(reasons),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_run_ts_suite_fit_validation <- function(
  out_dir,
  scenarios = NULL,
  kappa = 1,
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 180L,
  adaptive_vb_max_iter_grid = c(vb_max_iter, 360L),
  rhs_vb_inner = 5L,
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  sigma_upper_multiplier = 50,
  make_figures = TRUE,
  figure_case_limit = Inf
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_ts_synthetic_scenarios()
  if (anyDuplicated(scenarios$case_id)) {
    stop("Time-series suite scenarios must have unique case_id values.", call. = FALSE)
  }

  results <- vector("list", nrow(scenarios))
  for (ii in seq_len(nrow(scenarios))) {
    results[[ii]] <- app_joint_qvp_fit_ts_synthetic_scenario(
      sc = scenarios[ii, , drop = FALSE],
      out_dir = out_dir,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      rhs_vb_inner = rhs_vb_inner,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_seed_offset = mcmc_seed_offset,
      chain_seed_stride = chain_seed_stride,
      sigma_upper_multiplier = sigma_upper_multiplier,
      make_figures = isTRUE(make_figures) && ii <= figure_case_limit
    )
  }

  suite_fit_summary <- do.call(rbind, lapply(results, function(x) x$fit_summary))
  truth_fit_summary <- do.call(rbind, lapply(results, function(x) x$truth_fit_summary))
  readout_truth_summary <- do.call(rbind, lapply(results, function(x) x$readout_truth_summary))
  vb_mcmc_distance_summary <- do.call(rbind, lapply(results, function(x) x$vb_mcmc_distance_summary))
  chain_summary <- do.call(rbind, lapply(results, function(x) x$chain_summary))
  mcmc_draw_summary <- do.call(rbind, lapply(results, function(x) x$mcmc_draw_summary))
  crossing_summary <- do.call(rbind, lapply(results, function(x) x$crossing_summary))
  vb_convergence_audit <- app_bind_rows_fill(lapply(results, function(x) x$vb_convergence_audit))
  objective_diagnostics <- do.call(rbind, lapply(results, function(x) x$objective_diagnostics))
  elbo_terms <- do.call(rbind, lapply(results, function(x) x$elbo_terms))
  figure_manifest <- do.call(rbind, lapply(results, function(x) x$figure_manifest))
  figure_paths <- unlist(lapply(results, function(x) x$figure_paths), use.names = TRUE)
  suite_assessment <- app_joint_qvp_assess_ts_suite_fit_validation(
    suite_fit_summary,
    truth_fit_summary = truth_fit_summary
  )

  alpha_prior_mean_label <- if (is.null(alpha_prior_mean)) "none" else paste(as.character(alpha_prior_mean), collapse = ",")
  control_rows <- data.frame(
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean_label,
    alpha_prior_sd = alpha_prior_sd,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid), collapse = ","),
    rhs_vb_inner = rhs_vb_inner,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    make_figures = make_figures,
    figure_case_limit = figure_case_limit,
    stringsAsFactors = FALSE
  )
  run_config <- cbind(scenarios, control_rows[rep(1L, nrow(scenarios)), , drop = FALSE])

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    suite_assessment = app_joint_qvp_write_csv(suite_assessment, file.path(out_dir, "suite_assessment.csv")),
    suite_fit_summary = app_joint_qvp_write_csv(suite_fit_summary, file.path(out_dir, "suite_fit_summary.csv")),
    truth_fit_summary = app_joint_qvp_write_csv(truth_fit_summary, file.path(out_dir, "truth_fit_summary.csv")),
    readout_truth_summary = app_joint_qvp_write_csv(readout_truth_summary, file.path(out_dir, "readout_truth_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance_summary, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    chain_summary = app_joint_qvp_write_csv(chain_summary, file.path(out_dir, "chain_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(mcmc_draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence_audit, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective_diagnostics, file.path(out_dir, "objective_diagnostics.csv")),
    elbo_terms = app_joint_qvp_write_csv(elbo_terms, file.path(out_dir, "elbo_terms.csv")),
    figure_manifest = app_joint_qvp_write_csv(figure_manifest, file.path(out_dir, "figure_manifest.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  paths <- c(paths, figure_paths)
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    suite_assessment = suite_assessment,
    suite_fit_summary = suite_fit_summary,
    vb_convergence_audit = vb_convergence_audit
  )
}

app_joint_qvp_expand_ts_suite_calibration_scenarios <- function(
  scenarios = NULL,
  seeds = 20260701L + 0:4
) {
  base <- scenarios %||% app_joint_qvp_default_ts_synthetic_scenarios()
  seeds <- as.integer(seeds)
  if (!nrow(base)) stop("At least one base scenario is required.", call. = FALSE)
  if (!length(seeds) || any(is.na(seeds))) stop("At least one finite integer seed is required.", call. = FALSE)
  rows <- list()
  for (replicate_id in seq_along(seeds)) {
    for (ii in seq_len(nrow(base))) {
      sc <- base[ii, , drop = FALSE]
      base_case_id <- as.character(sc$case_id[[1L]])
      sc$base_case_id <- base_case_id
      sc$replicate_id <- as.integer(replicate_id)
      sc$seed <- seeds[[replicate_id]]
      sc$case_id <- sprintf("%s_rep%02d_seed%s", base_case_id, replicate_id, seeds[[replicate_id]])
      rows[[length(rows) + 1L]] <- sc
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

app_joint_qvp_ts_summary_stats <- function(x) {
  x <- as.numeric(x)
  finite <- x[is.finite(x)]
  q <- function(p) {
    if (length(finite)) as.numeric(stats::quantile(finite, probs = p, names = FALSE, na.rm = TRUE, type = 8)) else NA_real_
  }
  data.frame(
    n = length(x),
    n_finite = length(finite),
    mean = if (length(finite)) mean(finite) else NA_real_,
    sd = if (length(finite) > 1L) stats::sd(finite) else NA_real_,
    min = if (length(finite)) min(finite) else NA_real_,
    q50 = q(0.50),
    q80 = q(0.80),
    q90 = q(0.90),
    q95 = q(0.95),
    max = if (length(finite)) max(finite) else NA_real_,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_ts_metric_summary_rows <- function(
  data,
  metric_cols,
  group_cols = character(),
  scope,
  default_base_case_id = "ALL",
  default_likelihood = "ALL",
  default_fit = NA_character_,
  default_tau = NA_real_
) {
  if (!nrow(data) || !length(metric_cols)) return(data.frame())
  metric_cols <- intersect(metric_cols, names(data))
  if (!length(metric_cols)) return(data.frame())
  keys <- if (length(group_cols)) unique(data[, group_cols, drop = FALSE]) else data.frame(.all = "ALL")
  rows <- list()
  for (ii in seq_len(nrow(keys))) {
    idx <- rep(TRUE, nrow(data))
    if (length(group_cols)) {
      for (nm in group_cols) idx <- idx & data[[nm]] == keys[[nm]][[ii]]
    }
    for (metric in metric_cols) {
      stats <- app_joint_qvp_ts_summary_stats(data[[metric]][idx])
      rows[[length(rows) + 1L]] <- cbind(
        data.frame(
          scope = scope,
          base_case_id = if ("base_case_id" %in% group_cols) as.character(keys$base_case_id[[ii]]) else default_base_case_id,
          likelihood = if ("likelihood" %in% group_cols) as.character(keys$likelihood[[ii]]) else default_likelihood,
          fit = if ("fit" %in% group_cols) as.character(keys$fit[[ii]]) else default_fit,
          tau = if ("tau" %in% group_cols) as.numeric(keys$tau[[ii]]) else default_tau,
          metric = metric,
          stringsAsFactors = FALSE
        ),
        stats
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

app_joint_qvp_ts_gate_frequency_summary <- function(assessment) {
  if (!nrow(assessment)) return(data.frame())
  status_cols <- c(
    "implementation_status",
    "objective_gate_status",
    "truth_distance_status",
    "hit_rate_status",
    "vb_mcmc_status",
    "gate_status"
  )
  status_cols <- intersect(status_cols, names(assessment))
  rows <- list()
  for (base_case_id in unique(assessment$base_case_id)) {
    block <- assessment[assessment$base_case_id == base_case_id, , drop = FALSE]
    for (status_col in status_cols) {
      tab <- table(block[[status_col]])
      for (status in names(tab)) {
        rows[[length(rows) + 1L]] <- data.frame(
          base_case_id = base_case_id,
          status_type = status_col,
          status = status,
          n = as.integer(tab[[status]]),
          n_replicates = nrow(block),
          fraction = as.numeric(tab[[status]]) / nrow(block),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  all_block <- assessment
  for (status_col in status_cols) {
    tab <- table(all_block[[status_col]])
    for (status in names(tab)) {
      rows[[length(rows) + 1L]] <- data.frame(
        base_case_id = "ALL",
        status_type = status_col,
        status = status,
        n = as.integer(tab[[status]]),
        n_replicates = nrow(all_block),
        fraction = as.numeric(tab[[status]]) / nrow(all_block),
        stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

app_joint_qvp_ts_threshold_calibration_summary <- function(
  replicated_fit_summary,
  replicated_hit_rate_summary
) {
  fit_metric_cols <- c(
    "vb_truth_normalized_qhat_distance",
    "pooled_mcmc_truth_normalized_qhat_distance",
    "vb_mcmc_max_normalized_distance",
    "max_chain_to_pooled_normalized_distance",
    "max_abs_vb_hit_rate_error",
    "max_abs_pooled_mcmc_hit_rate_error",
    "max_sigma_upper_bound_hit_fraction",
    "total_vb_crossing_pairs",
    "total_pooled_mcmc_crossing_pairs",
    "objective_max_drop",
    "objective_n_decreases"
  )
  hit_rows <- replicated_hit_rate_summary
  hit_rows$abs_hit_rate_error <- abs(hit_rows$hit_rate_minus_tau)
  rbind(
    app_joint_qvp_ts_metric_summary_rows(
      replicated_fit_summary,
      fit_metric_cols,
      group_cols = character(),
      scope = "global_fit_summary"
    ),
    app_joint_qvp_ts_metric_summary_rows(
      replicated_fit_summary,
      fit_metric_cols,
      group_cols = c("base_case_id", "likelihood"),
      scope = "scenario_fit_summary"
    ),
    app_joint_qvp_ts_metric_summary_rows(
      hit_rows,
      "abs_hit_rate_error",
      group_cols = c("fit", "tau"),
      scope = "global_hit_rate"
    ),
    app_joint_qvp_ts_metric_summary_rows(
      hit_rows,
      "abs_hit_rate_error",
      group_cols = c("base_case_id", "likelihood", "fit", "tau"),
      scope = "scenario_hit_rate"
    )
  )
}

app_joint_qvp_ts_safe_quantile <- function(x, p = 0.95) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  as.numeric(stats::quantile(x, probs = p, names = FALSE, na.rm = TRUE, type = 8))
}

app_joint_qvp_ts_threshold_recommendations <- function(
  replicated_fit_summary,
  replicated_hit_rate_summary,
  replicated_assessment
) {
  rec <- list()
  add_metric <- function(metric, current_rule, current_numeric_threshold, candidate_floor, status, rationale) {
    x <- replicated_fit_summary[[metric]]
    q95 <- app_joint_qvp_ts_safe_quantile(x, 0.95)
    obs_max <- if (length(x)) max(as.numeric(x), na.rm = TRUE) else NA_real_
    candidate <- if (is.finite(q95)) max(candidate_floor, 1.25 * q95) else candidate_floor
    rec[[length(rec) + 1L]] <<- data.frame(
      metric = metric,
      current_rule = current_rule,
      current_numeric_threshold = current_numeric_threshold,
      observed_q95 = q95,
      observed_max = obs_max,
      candidate_review_threshold = candidate,
      recommendation_status = status,
      rationale = rationale,
      stringsAsFactors = FALSE
    )
  }
  add_metric(
    "vb_truth_normalized_qhat_distance",
    "<= 1.5 provisional pass",
    1.5,
    1.5,
    "retain_or_raise_after_more_seeds",
    "Use repeated seeds to calibrate AL-VB truth recovery under likelihood mismatch."
  )
  add_metric(
    "pooled_mcmc_truth_normalized_qhat_distance",
    "<= 2.0 provisional pass",
    2.0,
    2.0,
    "retain_or_raise_after_more_seeds",
    "Pooled MCMC is a short reference layer; do not make promotion claims from this alone."
  )
  add_metric(
    "vb_mcmc_max_normalized_distance",
    "<= 5 provisional pass",
    5.0,
    5.0,
    "retain_current_loose_threshold",
    "Current repeated-seed calibration checks VB/MCMC agreement, not final posterior accuracy."
  )
  add_metric(
    "max_chain_to_pooled_normalized_distance",
    "<= 5 provisional chain-stability review rule",
    5.0,
    5.0,
    "retain_current_loose_threshold",
    "Short chains should stay broadly stable before deep-chain reference promotion."
  )
  add_metric(
    "max_sigma_upper_bound_hit_fraction",
    "== 0 hard implementation gate",
    0.0,
    0.0,
    "hard_gate_keep_zero",
    "Positive sigma-bound hit fractions indicate bound-sensitive reference behavior."
  )
  add_metric(
    "total_vb_crossing_pairs",
    "== 0 hard implementation gate",
    0.0,
    0.0,
    "hard_gate_keep_zero",
    "Fitted quantile crossings remain an implementation hard gate for validation artifacts."
  )
  add_metric(
    "total_pooled_mcmc_crossing_pairs",
    "== 0 hard implementation gate",
    0.0,
    0.0,
    "hard_gate_keep_zero",
    "Pooled MCMC fitted crossings remain an implementation hard gate."
  )
  add_metric(
    "objective_max_drop",
    "<= 1e-8 accounted-objective pass",
    1.0e-8,
    1.0e-8,
    "review_only_until_elbo_accounting_resolved",
    "The current AL-VB objective is an accounted partial objective with RHS approximations."
  )

  hit_rows <- replicated_hit_rate_summary[replicated_hit_rate_summary$fit %in% c("vb", "pooled_mcmc"), , drop = FALSE]
  for (fit_label in c("vb", "pooled_mcmc")) {
    x <- abs(hit_rows$hit_rate_minus_tau[hit_rows$fit == fit_label])
    q95 <- app_joint_qvp_ts_safe_quantile(x, 0.95)
    obs_max <- if (length(x)) max(x, na.rm = TRUE) else NA_real_
    rec[[length(rec) + 1L]] <- data.frame(
      metric = paste0(fit_label, "_abs_hit_rate_error"),
      current_rule = "per tau: <= max(0.10, 2.5 * sqrt(tau * (1 - tau) / Tn))",
      current_numeric_threshold = NA_real_,
      observed_q95 = q95,
      observed_max = obs_max,
      candidate_review_threshold = if (is.finite(q95)) max(0.10, 1.25 * q95) else 0.10,
      recommendation_status = "calibrate_by_tau_and_Tn",
      rationale = "Hit-rate thresholds should remain finite-sample and tau-specific.",
      stringsAsFactors = FALSE
    )
  }

  gate_fail_rate <- mean(replicated_assessment$gate_status == "fail")
  rec[[length(rec) + 1L]] <- data.frame(
    metric = "overall_fail_fraction",
    current_rule = "must be 0 before application promotion",
    current_numeric_threshold = 0.0,
    observed_q95 = gate_fail_rate,
    observed_max = gate_fail_rate,
    candidate_review_threshold = 0.0,
    recommendation_status = "hard_gate_keep_zero",
    rationale = "Any repeated-seed hard failure requires targeted investigation before application promotion.",
    stringsAsFactors = FALSE
  )
  out <- do.call(rbind, rec)
  rownames(out) <- NULL
  out
}

app_joint_qvp_add_ts_replicate_meta <- function(x, sc) {
  x$base_case_id <- as.character(sc$base_case_id[[1L]])
  x$replicate_id <- as.integer(sc$replicate_id[[1L]])
  x$calibration_seed <- as.integer(sc$seed[[1L]])
  front <- intersect(c("case_id", "base_case_id", "replicate_id", "calibration_seed"), names(x))
  x[, c(front, setdiff(names(x), front)), drop = FALSE]
}

app_joint_qvp_run_ts_suite_threshold_calibration <- function(
  out_dir,
  scenarios = NULL,
  seeds = 20260701L + 0:4,
  kappa = 1,
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 180L,
  adaptive_vb_max_iter_grid = c(vb_max_iter, 360L, 500L),
  rhs_vb_inner = 5L,
  n_chains = 2L,
  mcmc_n_iter = 80L,
  mcmc_burn = 40L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  sigma_upper_multiplier = 50,
  make_figures = FALSE,
  figure_case_limit = 0L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  replicated_scenarios <- app_joint_qvp_expand_ts_suite_calibration_scenarios(scenarios, seeds)
  if (anyDuplicated(replicated_scenarios$case_id)) {
    stop("Replicated calibration scenarios must have unique case_id values.", call. = FALSE)
  }

  result_rows <- vector("list", nrow(replicated_scenarios))
  for (ii in seq_len(nrow(replicated_scenarios))) {
    sc <- replicated_scenarios[ii, , drop = FALSE]
    res <- app_joint_qvp_fit_ts_synthetic_scenario(
      sc = sc,
      out_dir = out_dir,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      rhs_vb_inner = rhs_vb_inner,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_seed_offset = mcmc_seed_offset,
      chain_seed_stride = chain_seed_stride,
      sigma_upper_multiplier = sigma_upper_multiplier,
      make_figures = isTRUE(make_figures) && ii <= figure_case_limit
    )
    fit_row <- res$fit_summary
    fit_row$objective_max_drop <- res$objective_diagnostics$max_drop[[1L]]
    fit_row$objective_n_decreases <- res$objective_diagnostics$n_decreases[[1L]]
    fit_row$objective_min_delta <- res$objective_diagnostics$min_delta[[1L]]
    hit_rows <- res$truth_fit_summary
    hit_rows$dynamic <- res$fixture$dynamic
    hit_rows$likelihood <- res$fixture$likelihood
    result_rows[[ii]] <- list(
      fit_summary = app_joint_qvp_add_ts_replicate_meta(fit_row, sc),
      truth_fit_summary = app_joint_qvp_add_ts_replicate_meta(hit_rows, sc),
      assessment = app_joint_qvp_add_ts_replicate_meta(
        app_joint_qvp_assess_ts_suite_fit_validation(fit_row, truth_fit_summary = res$truth_fit_summary),
        sc
      ),
      vb_convergence_audit = app_joint_qvp_add_ts_replicate_meta(res$vb_convergence_audit, sc),
      figure_manifest = res$figure_manifest,
      figure_paths = res$figure_paths
    )
  }

  replicated_fit_summary <- do.call(rbind, lapply(result_rows, `[[`, "fit_summary"))
  replicated_hit_rate_summary <- do.call(rbind, lapply(result_rows, `[[`, "truth_fit_summary"))
  replicated_assessment <- do.call(rbind, lapply(result_rows, `[[`, "assessment"))
  replicated_vb_convergence_audit <- app_bind_rows_fill(lapply(result_rows, `[[`, "vb_convergence_audit"))
  threshold_calibration_summary <- app_joint_qvp_ts_threshold_calibration_summary(
    replicated_fit_summary,
    replicated_hit_rate_summary
  )
  threshold_recommendations <- app_joint_qvp_ts_threshold_recommendations(
    replicated_fit_summary,
    replicated_hit_rate_summary,
    replicated_assessment
  )
  gate_frequency_summary <- app_joint_qvp_ts_gate_frequency_summary(replicated_assessment)
  figure_manifest <- do.call(rbind, lapply(result_rows, `[[`, "figure_manifest"))
  figure_paths <- unlist(lapply(result_rows, `[[`, "figure_paths"), use.names = TRUE)

  alpha_prior_mean_label <- if (is.null(alpha_prior_mean)) "none" else paste(as.character(alpha_prior_mean), collapse = ",")
  control_rows <- data.frame(
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean_label,
    alpha_prior_sd = alpha_prior_sd,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid), collapse = ","),
    rhs_vb_inner = rhs_vb_inner,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    make_figures = make_figures,
    figure_case_limit = figure_case_limit,
    stringsAsFactors = FALSE
  )
  replicated_run_config <- cbind(
    replicated_scenarios,
    control_rows[rep(1L, nrow(replicated_scenarios)), , drop = FALSE]
  )

  paths <- c(
    replicated_run_config = app_joint_qvp_write_csv(replicated_run_config, file.path(out_dir, "replicated_run_config.csv")),
    replicated_assessment = app_joint_qvp_write_csv(replicated_assessment, file.path(out_dir, "replicated_assessment.csv")),
    replicated_fit_summary = app_joint_qvp_write_csv(replicated_fit_summary, file.path(out_dir, "replicated_fit_summary.csv")),
    replicated_vb_convergence_audit = app_joint_qvp_write_csv(replicated_vb_convergence_audit, file.path(out_dir, "replicated_vb_convergence_audit.csv")),
    replicated_hit_rate_summary = app_joint_qvp_write_csv(replicated_hit_rate_summary, file.path(out_dir, "replicated_hit_rate_summary.csv")),
    threshold_calibration_summary = app_joint_qvp_write_csv(threshold_calibration_summary, file.path(out_dir, "threshold_calibration_summary.csv")),
    threshold_recommendations = app_joint_qvp_write_csv(threshold_recommendations, file.path(out_dir, "threshold_recommendations.csv")),
    gate_frequency_summary = app_joint_qvp_write_csv(gate_frequency_summary, file.path(out_dir, "gate_frequency_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  if (length(figure_paths)) {
    figure_manifest_path <- app_joint_qvp_write_csv(figure_manifest, file.path(out_dir, "figure_manifest.csv"))
    paths <- c(paths, figure_manifest = figure_manifest_path, figure_paths)
  }
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    replicated_fit_summary = replicated_fit_summary,
    replicated_assessment = replicated_assessment,
    replicated_vb_convergence_audit = replicated_vb_convergence_audit,
    threshold_calibration_summary = threshold_calibration_summary,
    threshold_recommendations = threshold_recommendations
  )
}

app_joint_qvp_select_ts_deep_mcmc_targets <- function(
  replicated_run_config,
  replicated_fit_summary,
  replicated_assessment = NULL,
  max_truth_targets = 1L,
  max_hit_targets = 3L,
  max_vb_mcmc_targets = 1L,
  max_objective_targets = 1L
) {
  if (!nrow(replicated_run_config) || !nrow(replicated_fit_summary)) {
    stop("Replicated run config and fit summary must be non-empty.", call. = FALSE)
  }
  add_reason <- function(targets, case_ids, reason) {
    case_ids <- unique(as.character(case_ids))
    case_ids <- case_ids[nzchar(case_ids)]
    if (!length(case_ids)) return(targets)
    for (case_id in case_ids) {
      hit <- match(case_id, targets$case_id)
      if (is.na(hit)) {
        targets <- rbind(
          targets,
          data.frame(
            case_id = case_id,
            target_order = nrow(targets) + 1L,
            target_reason = reason,
            stringsAsFactors = FALSE
          )
        )
      } else if (!grepl(reason, targets$target_reason[[hit]], fixed = TRUE)) {
        targets$target_reason[[hit]] <- paste(targets$target_reason[[hit]], reason, sep = ";")
      }
    }
    targets
  }
  top_case_ids <- function(metric, n, subset_case_ids = NULL) {
    n <- as.integer(n)
    if (n <= 0L || !metric %in% names(replicated_fit_summary)) return(character())
    rows <- replicated_fit_summary
    if (!is.null(subset_case_ids)) rows <- rows[rows$case_id %in% subset_case_ids, , drop = FALSE]
    rows <- rows[is.finite(rows[[metric]]), , drop = FALSE]
    if (!nrow(rows)) return(character())
    rows <- rows[order(-rows[[metric]], rows$case_id), , drop = FALSE]
    head(rows$case_id, n)
  }

  targets <- data.frame(case_id = character(), target_order = integer(), target_reason = character())
  truth_review_ids <- character()
  objective_review_ids <- character()
  if (!is.null(replicated_assessment) && nrow(replicated_assessment)) {
    truth_review_ids <- replicated_assessment$case_id[replicated_assessment$truth_distance_status != "pass"]
    objective_review_ids <- replicated_assessment$case_id[replicated_assessment$objective_gate_status != "pass"]
  }
  targets <- add_reason(
    targets,
    top_case_ids("pooled_mcmc_truth_normalized_qhat_distance", max_truth_targets, truth_review_ids),
    "truth_distance_review"
  )
  if (!nrow(targets) && max_truth_targets > 0L) {
    targets <- add_reason(
      targets,
      top_case_ids("pooled_mcmc_truth_normalized_qhat_distance", max_truth_targets),
      "truth_distance_top"
    )
  }
  targets <- add_reason(
    targets,
    top_case_ids("max_abs_pooled_mcmc_hit_rate_error", max_hit_targets),
    "pooled_mcmc_hit_error_top"
  )
  targets <- add_reason(
    targets,
    top_case_ids("vb_mcmc_max_normalized_distance", max_vb_mcmc_targets),
    "vb_mcmc_distance_top"
  )
  targets <- add_reason(
    targets,
    top_case_ids("objective_max_drop", max_objective_targets, objective_review_ids),
    "objective_drop_top"
  )
  if (!nrow(targets)) stop("No deep-MCMC targets were selected.", call. = FALSE)

  scenario_cols <- c(names(app_joint_qvp_default_ts_synthetic_scenarios()), "base_case_id", "replicate_id")
  scenario_cols <- intersect(scenario_cols, names(replicated_run_config))
  selected <- merge(targets, replicated_run_config[, scenario_cols, drop = FALSE], by = "case_id", all.x = TRUE, sort = FALSE)
  selected <- selected[order(selected$target_order), , drop = FALSE]
  if (any(is.na(selected$seed))) {
    stop("Selected target case IDs were not all found in replicated_run_config.", call. = FALSE)
  }
  rownames(selected) <- NULL
  selected
}

app_joint_qvp_deep_reference_comparison_row <- function(
  target,
  shallow_fit,
  shallow_assessment,
  deep_fit,
  deep_assessment
) {
  metric_delta <- function(metric) {
    if (!metric %in% names(shallow_fit) || !metric %in% names(deep_fit)) return(NA_real_)
    as.numeric(deep_fit[[metric]][[1L]]) - as.numeric(shallow_fit[[metric]][[1L]])
  }
  shallow_truth_status <- if (nrow(shallow_assessment)) shallow_assessment$truth_distance_status[[1L]] else NA_character_
  shallow_hit_status <- if (nrow(shallow_assessment)) shallow_assessment$hit_rate_status[[1L]] else NA_character_
  deep_truth_status <- deep_assessment$truth_distance_status[[1L]]
  deep_hit_status <- deep_assessment$hit_rate_status[[1L]]
  hard_fail <- identical(deep_assessment$implementation_status[[1L]], "fail")
  truth_delta <- metric_delta("pooled_mcmc_truth_normalized_qhat_distance")
  hit_delta <- metric_delta("max_abs_pooled_mcmc_hit_rate_error")
  interpretation <- if (hard_fail) {
    "deep_reference_hard_fail"
  } else if (!identical(shallow_truth_status, "pass") && identical(deep_truth_status, "pass")) {
    "deep_reference_resolves_truth_review"
  } else if (!identical(shallow_truth_status, "pass") && !identical(deep_truth_status, "pass")) {
    "persistent_truth_review_under_deep_reference"
  } else if (!identical(shallow_hit_status, "pass") && identical(deep_hit_status, "pass")) {
    "deep_reference_resolves_hit_review"
  } else if ((is.finite(truth_delta) && truth_delta <= -0.25) || (is.finite(hit_delta) && hit_delta <= -0.05)) {
    "deep_reference_improves_review_metric"
  } else if (!identical(deep_truth_status, "pass") || !identical(deep_hit_status, "pass")) {
    "persistent_review_under_deep_reference"
  } else {
    "deep_reference_stable"
  }
  data.frame(
    case_id = target$case_id[[1L]],
    base_case_id = target$base_case_id[[1L]],
    replicate_id = as.integer(target$replicate_id[[1L]]),
    calibration_seed = as.integer(target$seed[[1L]]),
    target_reason = target$target_reason[[1L]],
    shallow_n_chains = as.integer(shallow_fit$n_chains[[1L]]),
    shallow_mcmc_n_iter = as.integer(shallow_fit$mcmc_n_iter[[1L]]),
    shallow_mcmc_n_keep_total = as.integer(shallow_fit$mcmc_n_keep_total[[1L]]),
    deep_n_chains = as.integer(deep_fit$n_chains[[1L]]),
    deep_mcmc_n_iter = as.integer(deep_fit$mcmc_n_iter[[1L]]),
    deep_mcmc_n_keep_total = as.integer(deep_fit$mcmc_n_keep_total[[1L]]),
    shallow_pooled_mcmc_truth_normalized_qhat_distance = shallow_fit$pooled_mcmc_truth_normalized_qhat_distance[[1L]],
    deep_pooled_mcmc_truth_normalized_qhat_distance = deep_fit$pooled_mcmc_truth_normalized_qhat_distance[[1L]],
    delta_pooled_mcmc_truth_normalized_qhat_distance = truth_delta,
    shallow_vb_mcmc_max_normalized_distance = shallow_fit$vb_mcmc_max_normalized_distance[[1L]],
    deep_vb_mcmc_max_normalized_distance = deep_fit$vb_mcmc_max_normalized_distance[[1L]],
    delta_vb_mcmc_max_normalized_distance = metric_delta("vb_mcmc_max_normalized_distance"),
    shallow_max_abs_pooled_mcmc_hit_rate_error = shallow_fit$max_abs_pooled_mcmc_hit_rate_error[[1L]],
    deep_max_abs_pooled_mcmc_hit_rate_error = deep_fit$max_abs_pooled_mcmc_hit_rate_error[[1L]],
    delta_max_abs_pooled_mcmc_hit_rate_error = hit_delta,
    deep_max_chain_to_pooled_normalized_distance = deep_fit$max_chain_to_pooled_normalized_distance[[1L]],
    deep_total_vb_crossing_pairs = deep_fit$total_vb_crossing_pairs[[1L]],
    deep_total_pooled_mcmc_crossing_pairs = deep_fit$total_pooled_mcmc_crossing_pairs[[1L]],
    deep_max_sigma_upper_bound_hit_fraction = deep_fit$max_sigma_upper_bound_hit_fraction[[1L]],
    shallow_truth_distance_status = shallow_truth_status,
    deep_truth_distance_status = deep_truth_status,
    shallow_hit_rate_status = shallow_hit_status,
    deep_hit_rate_status = deep_hit_status,
    deep_implementation_status = deep_assessment$implementation_status[[1L]],
    deep_gate_status = deep_assessment$gate_status[[1L]],
    deepening_interpretation = interpretation,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_deep_reference_resolution_summary <- function(comparison) {
  if (!nrow(comparison)) return(data.frame())
  rows <- as.data.frame(table(comparison$deepening_interpretation), stringsAsFactors = FALSE)
  names(rows) <- c("deepening_interpretation", "n")
  rows$fraction <- rows$n / nrow(comparison)
  rows
}

app_joint_qvp_run_ts_deep_mcmc_reference <- function(
  out_dir,
  calibration_dir = file.path(app_repo_root(), "application/cache/joint_qvp_ts_suite_threshold_calibration_20260701"),
  replicated_run_config = NULL,
  replicated_fit_summary = NULL,
  replicated_assessment = NULL,
  targets = NULL,
  max_truth_targets = 1L,
  max_hit_targets = 3L,
  max_vb_mcmc_targets = 1L,
  max_objective_targets = 1L,
  kappa = 1,
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 220L,
  adaptive_vb_max_iter_grid = c(vb_max_iter, 360L, 500L),
  rhs_vb_inner = 5L,
  n_chains = 4L,
  mcmc_n_iter = 300L,
  mcmc_burn = 150L,
  mcmc_thin = 10L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  sigma_upper_multiplier = 50,
  make_figures = TRUE,
  figure_case_limit = Inf,
  verbose = TRUE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(replicated_run_config)) {
    replicated_run_config <- utils::read.csv(file.path(calibration_dir, "replicated_run_config.csv"), stringsAsFactors = FALSE)
  }
  if (is.null(replicated_fit_summary)) {
    replicated_fit_summary <- utils::read.csv(file.path(calibration_dir, "replicated_fit_summary.csv"), stringsAsFactors = FALSE)
  }
  if (is.null(replicated_assessment)) {
    replicated_assessment <- utils::read.csv(file.path(calibration_dir, "replicated_assessment.csv"), stringsAsFactors = FALSE)
  }
  if (is.null(targets)) {
    targets <- app_joint_qvp_select_ts_deep_mcmc_targets(
      replicated_run_config = replicated_run_config,
      replicated_fit_summary = replicated_fit_summary,
      replicated_assessment = replicated_assessment,
      max_truth_targets = max_truth_targets,
      max_hit_targets = max_hit_targets,
      max_vb_mcmc_targets = max_vb_mcmc_targets,
      max_objective_targets = max_objective_targets
    )
  }
  if (!nrow(targets)) stop("At least one deep-MCMC target is required.", call. = FALSE)

  result_rows <- vector("list", nrow(targets))
  for (ii in seq_len(nrow(targets))) {
    target <- targets[ii, , drop = FALSE]
    if (isTRUE(verbose)) {
      message(sprintf("Deep MCMC target %s/%s: %s", ii, nrow(targets), target$case_id[[1L]]))
    }
    res <- app_joint_qvp_fit_ts_synthetic_scenario(
      sc = target,
      out_dir = out_dir,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      vb_max_iter = vb_max_iter,
      adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
      rhs_vb_inner = rhs_vb_inner,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_seed_offset = mcmc_seed_offset,
      chain_seed_stride = chain_seed_stride,
      sigma_upper_multiplier = sigma_upper_multiplier,
      make_figures = isTRUE(make_figures) && ii <= figure_case_limit
    )
    fit_row <- res$fit_summary
    fit_row$objective_max_drop <- res$objective_diagnostics$max_drop[[1L]]
    fit_row$objective_n_decreases <- res$objective_diagnostics$n_decreases[[1L]]
    fit_row$objective_min_delta <- res$objective_diagnostics$min_delta[[1L]]
    fit_row$target_reason <- target$target_reason[[1L]]
    hit_rows <- res$truth_fit_summary
    hit_rows$dynamic <- res$fixture$dynamic
    hit_rows$likelihood <- res$fixture$likelihood
    hit_rows$target_reason <- target$target_reason[[1L]]
    deep_assessment <- app_joint_qvp_assess_ts_suite_fit_validation(fit_row, truth_fit_summary = res$truth_fit_summary)
    deep_assessment$target_reason <- target$target_reason[[1L]]
    shallow_fit <- replicated_fit_summary[replicated_fit_summary$case_id == target$case_id[[1L]], , drop = FALSE]
    shallow_assessment <- replicated_assessment[replicated_assessment$case_id == target$case_id[[1L]], , drop = FALSE]
    comparison <- app_joint_qvp_deep_reference_comparison_row(
      target = target,
      shallow_fit = shallow_fit,
      shallow_assessment = shallow_assessment,
      deep_fit = fit_row,
      deep_assessment = deep_assessment
    )
    result_rows[[ii]] <- list(
      fit_summary = app_joint_qvp_add_ts_replicate_meta(fit_row, target),
      hit_rate_summary = app_joint_qvp_add_ts_replicate_meta(hit_rows, target),
      assessment = app_joint_qvp_add_ts_replicate_meta(deep_assessment, target),
      comparison = comparison,
      vb_mcmc_distance_summary = app_joint_qvp_add_ts_replicate_meta(res$vb_mcmc_distance_summary, target),
      chain_summary = app_joint_qvp_add_ts_replicate_meta(res$chain_summary, target),
      draw_summary = app_joint_qvp_add_ts_replicate_meta(res$mcmc_draw_summary, target),
      crossing_summary = app_joint_qvp_add_ts_replicate_meta(res$crossing_summary, target),
      vb_convergence_audit = app_joint_qvp_add_ts_replicate_meta(res$vb_convergence_audit, target),
      objective_diagnostics = app_joint_qvp_add_ts_replicate_meta(res$objective_diagnostics, target),
      elbo_terms = app_joint_qvp_add_ts_replicate_meta(res$elbo_terms, target),
      figure_manifest = res$figure_manifest,
      figure_paths = res$figure_paths
    )
  }

  deep_fit_summary <- do.call(rbind, lapply(result_rows, `[[`, "fit_summary"))
  deep_hit_rate_summary <- do.call(rbind, lapply(result_rows, `[[`, "hit_rate_summary"))
  deep_assessment <- do.call(rbind, lapply(result_rows, `[[`, "assessment"))
  deep_comparison <- do.call(rbind, lapply(result_rows, `[[`, "comparison"))
  vb_mcmc_distance_summary <- do.call(rbind, lapply(result_rows, `[[`, "vb_mcmc_distance_summary"))
  chain_summary <- do.call(rbind, lapply(result_rows, `[[`, "chain_summary"))
  draw_summary <- do.call(rbind, lapply(result_rows, `[[`, "draw_summary"))
  crossing_summary <- do.call(rbind, lapply(result_rows, `[[`, "crossing_summary"))
  vb_convergence_audit <- app_bind_rows_fill(lapply(result_rows, `[[`, "vb_convergence_audit"))
  objective_diagnostics <- do.call(rbind, lapply(result_rows, `[[`, "objective_diagnostics"))
  elbo_terms <- do.call(rbind, lapply(result_rows, `[[`, "elbo_terms"))
  resolution_summary <- app_joint_qvp_deep_reference_resolution_summary(deep_comparison)
  figure_manifest <- do.call(rbind, lapply(result_rows, `[[`, "figure_manifest"))
  figure_paths <- unlist(lapply(result_rows, `[[`, "figure_paths"), use.names = TRUE)

  alpha_prior_mean_label <- if (is.null(alpha_prior_mean)) "none" else paste(as.character(alpha_prior_mean), collapse = ",")
  control_rows <- data.frame(
    kappa = kappa,
    tau0 = tau0,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean_label,
    alpha_prior_sd = alpha_prior_sd,
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = paste(app_joint_qvp_normalize_vb_max_iter_grid(vb_max_iter, adaptive_vb_max_iter_grid), collapse = ","),
    rhs_vb_inner = rhs_vb_inner,
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    make_figures = make_figures,
    figure_case_limit = figure_case_limit,
    stringsAsFactors = FALSE
  )
  deep_run_config <- cbind(targets, control_rows[rep(1L, nrow(targets)), , drop = FALSE])
  paths <- c(
    target_selection = app_joint_qvp_write_csv(targets, file.path(out_dir, "target_selection.csv")),
    deep_reference_run_config = app_joint_qvp_write_csv(deep_run_config, file.path(out_dir, "deep_reference_run_config.csv")),
    deep_reference_assessment = app_joint_qvp_write_csv(deep_assessment, file.path(out_dir, "deep_reference_assessment.csv")),
    deep_reference_comparison = app_joint_qvp_write_csv(deep_comparison, file.path(out_dir, "deep_reference_comparison.csv")),
    deep_reference_resolution_summary = app_joint_qvp_write_csv(resolution_summary, file.path(out_dir, "deep_reference_resolution_summary.csv")),
    deep_reference_fit_summary = app_joint_qvp_write_csv(deep_fit_summary, file.path(out_dir, "deep_reference_fit_summary.csv")),
    deep_reference_hit_rate_summary = app_joint_qvp_write_csv(deep_hit_rate_summary, file.path(out_dir, "deep_reference_hit_rate_summary.csv")),
    deep_reference_vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance_summary, file.path(out_dir, "deep_reference_vb_mcmc_distance_summary.csv")),
    deep_reference_chain_summary = app_joint_qvp_write_csv(chain_summary, file.path(out_dir, "deep_reference_chain_summary.csv")),
    deep_reference_mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "deep_reference_mcmc_draw_summary.csv")),
    deep_reference_crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "deep_reference_crossing_summary.csv")),
    deep_reference_vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence_audit, file.path(out_dir, "deep_reference_vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective_diagnostics, file.path(out_dir, "objective_diagnostics.csv")),
    elbo_terms = app_joint_qvp_write_csv(elbo_terms, file.path(out_dir, "elbo_terms.csv")),
    figure_manifest = app_joint_qvp_write_csv(figure_manifest, file.path(out_dir, "figure_manifest.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  paths <- c(paths, figure_paths)
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    target_selection = targets,
    deep_reference_assessment = deep_assessment,
    deep_reference_comparison = deep_comparison,
    deep_reference_fit_summary = deep_fit_summary,
    deep_reference_vb_convergence_audit = vb_convergence_audit
  )
}

app_joint_qvp_profile_check_loss_rows <- function(fixture, qhat, case_id, fit_label, fit_type, kappa = NA_real_) {
  qhat <- as.matrix(qhat)
  if (!identical(dim(qhat), dim(fixture$true_q))) {
    stop("qhat must have the same dimensions as fixture$true_q.", call. = FALSE)
  }
  truth_summary <- app_joint_qvp_qhat_truth_summary(fixture, qhat, fit_label, case_id)
  rows <- lapply(seq_along(fixture$tau), function(k) {
    check_loss <- app_joint_qvp_check_loss(fixture$y - qhat[, k], fixture$tau[[k]])
    cbind(
      truth_summary[truth_summary$quantile_index == k, , drop = FALSE],
      data.frame(
        fit_type = fit_type,
        kappa = as.numeric(kappa),
        check_loss = check_loss,
        profiled_sigma_hat = check_loss / length(fixture$y),
        stringsAsFactors = FALSE
      )
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_extreme_fit_summary_rows <- function(fit_diagnostics) {
  split_rows <- split(fit_diagnostics, paste(fit_diagnostics$case_id, fit_diagnostics$fit, sep = "\r"))
  out <- lapply(split_rows, function(block) {
    tau_min <- min(block$tau)
    tau_max <- max(block$tau)
    tail_block <- block[block$tau %in% c(tau_min, tau_max), , drop = FALSE]
    data.frame(
      case_id = block$case_id[[1L]],
      fit = block$fit[[1L]],
      fit_type = block$fit_type[[1L]],
      kappa = block$kappa[[1L]],
      max_rmse_to_truth = max(block$rmse_to_truth),
      max_tail_rmse_to_truth = max(tail_block$rmse_to_truth),
      max_abs_mean_error_to_truth = max(abs(block$mean_error_to_truth)),
      max_abs_hit_rate_error = max(abs(block$hit_rate_minus_tau)),
      max_tail_abs_hit_rate_error = max(abs(tail_block$hit_rate_minus_tau)),
      max_check_loss_ratio_to_qr = max(block$check_loss_ratio_to_qr, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  ans <- do.call(rbind, out)
  rownames(ans) <- NULL
  ans
}

app_joint_qvp_run_ts_extreme_tail_fit_audit <- function(
  out_dir,
  scenarios = NULL,
  vb_kappa_values = c(0.5, 1),
  mcmc_case_ids = "ts_asymmetric_laplace_tail",
  mcmc_kappa_values = c(0.5, 1),
  tau0 = 1,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_mean = "empirical_quantile",
  alpha_prior_sd = 1,
  vb_max_iter = 300L,
  rhs_vb_inner = 5L,
  mcmc_n_iter = 300L,
  mcmc_burn = 150L,
  mcmc_thin = 5L,
  mcmc_seed_offset = 7100L,
  sigma_upper_multiplier = 50
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_ts_synthetic_scenarios()
  if (anyDuplicated(scenarios$case_id)) {
    stop("Audit scenarios must have unique case_id values.", call. = FALSE)
  }

  diagnostic_rows <- list()
  baseline_rows <- list()
  control_rows <- list()
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, , drop = FALSE]
    case_id <- as.character(sc$case_id[[1L]])
    fixture <- app_joint_qvp_ts_fixture_from_scenario(sc)

    truth_rows <- app_joint_qvp_profile_check_loss_rows(
      fixture = fixture,
      qhat = fixture$true_q,
      case_id = case_id,
      fit_label = "truth",
      fit_type = "truth",
      kappa = NA_real_
    )
    diagnostic_rows[[length(diagnostic_rows) + 1L]] <- truth_rows

    qr_fit <- app_joint_qvp_fit_check_loss_baseline(fixture)
    qr_rows <- app_joint_qvp_profile_check_loss_rows(
      fixture = fixture,
      qhat = qr_fit$qhat_mean,
      case_id = case_id,
      fit_label = "check_loss_qr",
      fit_type = "check_loss_baseline",
      kappa = NA_real_
    )
    qr_rows <- merge(qr_rows, qr_fit$summary[, c("quantile_index", "convergence")],
      by = "quantile_index", suffixes = c("", "_optim"), sort = FALSE)
    diagnostic_rows[[length(diagnostic_rows) + 1L]] <- qr_rows
    baseline_rows[[length(baseline_rows) + 1L]] <- data.frame(
      case_id = case_id,
      quantile_index = qr_fit$summary$quantile_index,
      tau = qr_fit$summary$tau,
      check_loss_qr = qr_fit$summary$check_loss,
      check_loss_convergence = qr_fit$summary$convergence,
      check_loss_sigma_hat = qr_fit$summary$sigma_hat,
      stringsAsFactors = FALSE
    )

    for (kappa in vb_kappa_values) {
      vb_fit <- app_joint_qvp_fit_al_vb_tiny(
        y = fixture$y,
        Z = fixture$Z,
        tau = fixture$tau,
        max_iter = vb_max_iter,
        tol = 1.0e-4,
        kappa = kappa,
        tau0 = tau0,
        a_sigma = a_sigma,
        b_sigma = b_sigma,
        alpha_prior_mean = alpha_prior_mean,
        alpha_prior_sd = alpha_prior_sd,
        rhs_vb_inner = rhs_vb_inner
      )
      fit_label <- sprintf("al_vb_kappa_%s", format(kappa, trim = TRUE, scientific = FALSE))
      vb_rows <- app_joint_qvp_profile_check_loss_rows(
        fixture = fixture,
        qhat = vb_fit$qhat_mean,
        case_id = case_id,
        fit_label = fit_label,
        fit_type = "al_vb",
        kappa = kappa
      )
      vb_rows$fit_converged <- isTRUE(vb_fit$converged)
      vb_rows$fit_n_iter <- nrow(vb_fit$trace)
      vb_rows$fit_objective_status <- vb_fit$objective_diagnostics$objective_status[[1L]]
      vb_rows$fit_sigma_mean <- vb_fit$sigma_mean[vb_rows$quantile_index]
      vb_rows$fit_alpha_mean <- vb_fit$alpha_mean[vb_rows$quantile_index]
      diagnostic_rows[[length(diagnostic_rows) + 1L]] <- vb_rows
      control_rows[[length(control_rows) + 1L]] <- data.frame(
        case_id = case_id,
        fit = fit_label,
        fit_type = "al_vb",
        kappa = kappa,
        converged = isTRUE(vb_fit$converged),
        n_iter = nrow(vb_fit$trace),
        objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
        stringsAsFactors = FALSE
      )
    }

    if (case_id %in% mcmc_case_ids) {
      for (kappa in mcmc_kappa_values) {
        vb_init <- app_joint_qvp_fit_al_vb_tiny(
          y = fixture$y,
          Z = fixture$Z,
          tau = fixture$tau,
          max_iter = vb_max_iter,
          tol = 1.0e-4,
          kappa = kappa,
          tau0 = tau0,
          a_sigma = a_sigma,
          b_sigma = b_sigma,
          alpha_prior_mean = alpha_prior_mean,
          alpha_prior_sd = alpha_prior_sd,
          rhs_vb_inner = rhs_vb_inner
        )
        sigma_upper_bound <- max(1, sigma_upper_multiplier * max(vb_init$sigma_mean))
        mcmc_fit <- app_joint_qvp_fit_al_mcmc_tiny(
          y = fixture$y,
          Z = fixture$Z,
          tau = fixture$tau,
          n_iter = mcmc_n_iter,
          burn = mcmc_burn,
          thin = mcmc_thin,
          seed = as.integer(sc$seed[[1L]]) + mcmc_seed_offset + as.integer(round(100 * kappa)),
          kappa = kappa,
          tau0 = tau0,
          a_sigma = a_sigma,
          b_sigma = b_sigma,
          alpha_prior_mean = alpha_prior_mean,
          alpha_prior_sd = alpha_prior_sd,
          init = vb_init,
          max_dense_dim = 100L,
          sigma_bounds = c(1.0e-8, sigma_upper_bound)
        )
        fit_label <- sprintf("al_mcmc_kappa_%s", format(kappa, trim = TRUE, scientific = FALSE))
        mcmc_rows <- app_joint_qvp_profile_check_loss_rows(
          fixture = fixture,
          qhat = mcmc_fit$qhat_mean,
          case_id = case_id,
          fit_label = fit_label,
          fit_type = "al_mcmc",
          kappa = kappa
        )
        mcmc_rows$fit_converged <- NA
        mcmc_rows$fit_n_iter <- mcmc_n_iter
        mcmc_rows$fit_objective_status <- NA_character_
        mcmc_rows$fit_sigma_mean <- mcmc_fit$sigma_mean[mcmc_rows$quantile_index]
        mcmc_rows$fit_alpha_mean <- mcmc_fit$alpha_mean[mcmc_rows$quantile_index]
        diagnostic_rows[[length(diagnostic_rows) + 1L]] <- mcmc_rows
        control_rows[[length(control_rows) + 1L]] <- data.frame(
          case_id = case_id,
          fit = fit_label,
          fit_type = "al_mcmc",
          kappa = kappa,
          converged = NA,
          n_iter = mcmc_n_iter,
          objective_status = NA_character_,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  fit_diagnostics <- app_bind_rows_fill(diagnostic_rows)
  baseline <- app_bind_rows_fill(baseline_rows)
  fit_diagnostics <- merge(
    fit_diagnostics,
    baseline[, c("case_id", "quantile_index", "check_loss_qr")],
    by = c("case_id", "quantile_index"),
    all.x = TRUE,
    sort = FALSE
  )
  fit_diagnostics$check_loss_ratio_to_qr <- fit_diagnostics$check_loss / fit_diagnostics$check_loss_qr
  fit_diagnostics <- fit_diagnostics[order(fit_diagnostics$case_id, fit_diagnostics$fit, fit_diagnostics$tau), , drop = FALSE]
  audit_summary <- app_joint_qvp_extreme_fit_summary_rows(fit_diagnostics)
  controls <- app_bind_rows_fill(control_rows)

  asym <- fit_diagnostics[fit_diagnostics$case_id == "ts_asymmetric_laplace_tail", , drop = FALSE]
  asym_summary <- audit_summary[audit_summary$case_id == "ts_asymmetric_laplace_tail", , drop = FALSE]
  get_asym <- function(fit, tau, col) {
    val <- asym[asym$fit == fit & abs(asym$tau - tau) < 1.0e-12, col]
    if (length(val)) val[[1L]] else NA_real_
  }
  get_asym_summary <- function(fit, col) {
    val <- asym_summary[asym_summary$fit == fit, col]
    if (length(val)) val[[1L]] else NA_real_
  }
  report <- c(
    "# Joint-QVP Extreme-Tail Fit Calibration Audit",
    "",
    "Date: 2026-07-02",
    "",
    "## Conclusion",
    "",
    "The extreme-tail failure is not caused by the synthetic DGP being unidentifiable. A direct check-loss quantile-regression baseline recovers the true tail paths. The failure is caused by using `kappa = 0.5` inside the complete-data AL latent augmentation for the main validation lane.",
    "",
    "Tempering the augmented joint AL density is not equivalent to tempering the observed AL check-loss likelihood after integrating latent variables. With `kappa = 0.5`, the current latent VB/MCMC target pushes the lower quantile below all observations and the upper quantile above all observations. With `kappa = 1`, VB and MCMC recover the asymmetric-Laplace tails.",
    "",
    "## Asymmetric-Laplace Tail Case",
    "",
    sprintf("- Check-loss QR max tail RMSE: %.3f.", get_asym_summary("check_loss_qr", "max_tail_rmse_to_truth")),
    sprintf("- AL-VB kappa 0.5 max tail RMSE: %.3f.", get_asym_summary("al_vb_kappa_0.5", "max_tail_rmse_to_truth")),
    sprintf("- AL-VB kappa 1 max tail RMSE: %.3f.", get_asym_summary("al_vb_kappa_1", "max_tail_rmse_to_truth")),
    sprintf("- AL-MCMC kappa 0.5 max tail RMSE: %.3f.", get_asym_summary("al_mcmc_kappa_0.5", "max_tail_rmse_to_truth")),
    sprintf("- AL-MCMC kappa 1 max tail RMSE: %.3f.", get_asym_summary("al_mcmc_kappa_1", "max_tail_rmse_to_truth")),
    sprintf("- AL-VB kappa 0.5 tau 0.10 hit: %.3f; tau 0.90 hit: %.3f.", get_asym("al_vb_kappa_0.5", 0.1, "empirical_hit_rate"), get_asym("al_vb_kappa_0.5", 0.9, "empirical_hit_rate")),
    sprintf("- AL-VB kappa 1 tau 0.10 hit: %.3f; tau 0.90 hit: %.3f.", get_asym("al_vb_kappa_1", 0.1, "empirical_hit_rate"), get_asym("al_vb_kappa_1", 0.9, "empirical_hit_rate")),
    "",
    "## Implementation Decision",
    "",
    "- Main synthetic validation defaults are calibrated to `kappa = 1`.",
    "- `kappa = 0.5` should be retained only as an explicit stress/mis-target diagnostic until a marginal-likelihood-safe tempering derivation is implemented.",
    "- The regenerated figures should be interpreted against the `kappa = 1` validation lane."
  )

  paths <- c(
    fit_diagnostics = app_joint_qvp_write_csv(fit_diagnostics, file.path(out_dir, "fit_diagnostics.csv")),
    audit_summary = app_joint_qvp_write_csv(audit_summary, file.path(out_dir, "audit_summary.csv")),
    check_loss_baseline = app_joint_qvp_write_csv(baseline, file.path(out_dir, "check_loss_baseline.csv")),
    audit_controls = app_joint_qvp_write_csv(controls, file.path(out_dir, "audit_controls.csv"))
  )
  report_path <- file.path(out_dir, "audit_report.md")
  writeLines(report, report_path)
  paths <- c(paths, audit_report = normalizePath(report_path, mustWork = TRUE))
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    fit_diagnostics = fit_diagnostics,
    audit_summary = audit_summary
  )
}

app_joint_qvp_collect_temp_figure_review <- function(
  out_dir,
  toy_dir = app_path("application/cache/joint_qvp_ts_toy_fit_validation_20260701"),
  suite_dir = app_path("application/cache/joint_qvp_ts_suite_fit_validation_20260701"),
  deep_dir = app_path("application/cache/joint_qvp_ts_deep_mcmc_reference_20260701"),
  wide_dir = app_path("application/cache/joint_qvp_temp_diagnostics_20260701"),
  suite_case_ids = sort(app_joint_qvp_default_ts_synthetic_scenarios()$case_id),
  generated_time = Sys.time()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  add_figure <- function(rows, stage, priority, source_path) {
    rows[[length(rows) + 1L]] <- data.frame(
      stage = stage,
      priority = priority,
      source_path = source_path,
      stringsAsFactors = FALSE
    )
    rows
  }
  png_path <- function(dir, name) file.path(dir, paste0(name, ".png"))
  read_manifest <- function(dir) {
    path <- file.path(dir, "figure_manifest.csv")
    if (!file.exists(path)) return(NULL)
    utils::read.csv(path, stringsAsFactors = FALSE)
  }
  html_escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    gsub('"', "&quot;", x, fixed = TRUE)
  }
  regex_escape <- function(x) {
    gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
  }

  stage_rows <- list()
  toy_dir <- normalizePath(toy_dir, mustWork = FALSE)
  suite_dir <- normalizePath(suite_dir, mustWork = FALSE)
  deep_dir <- normalizePath(deep_dir, mustWork = FALSE)
  wide_dir <- normalizePath(wide_dir, mustWork = FALSE)

  toy_manifest <- read_manifest(toy_dir)
  if (!is.null(toy_manifest)) {
    toy_order <- c("error_hit", "fit_overlay", "elbo_trace", "parameter_traces")
    toy_manifest$.order <- match(toy_manifest$label, toy_order)
    toy_manifest <- toy_manifest[order(is.na(toy_manifest$.order), toy_manifest$.order, toy_manifest$label), , drop = FALSE]
    for (ii in seq_len(nrow(toy_manifest))) {
      label <- toy_manifest$label[[ii]]
      stage_rows <- add_figure(
        stage_rows,
        "01_toy_fit_validation",
        paste0("toy_", label),
        file.path(toy_dir, toy_manifest$relative_path[[ii]])
      )
    }
  } else {
    toy_case <- "ts_toy_student_t_seed20260701_K3"
    for (suffix in c("error_hit", "fit_overlay", "elbo_trace", "parameter_traces")) {
      stage_rows <- add_figure(
        stage_rows,
        "01_toy_fit_validation",
        paste0("toy_", suffix),
        png_path(toy_dir, paste(toy_case, suffix, sep = "_"))
      )
    }
  }

  for (case_id in suite_case_ids) {
    stage_rows <- add_figure(
      stage_rows,
      "02_suite_fit_validation",
      "suite_error_hit",
      png_path(suite_dir, paste(case_id, "error_hit", sep = "_"))
    )
    stage_rows <- add_figure(
      stage_rows,
      "02_suite_fit_validation",
      "suite_fit_overlay",
      png_path(suite_dir, paste(case_id, "fit_overlay", sep = "_"))
    )
  }

  deep_manifest <- read_manifest(deep_dir)
  if (!is.null(deep_manifest)) {
    deep_manifest <- deep_manifest[grepl("(_error_hit|_fit_overlay)[.]png$", deep_manifest$relative_path), , drop = FALSE]
    deep_files <- file.path(deep_dir, deep_manifest$relative_path)
  } else {
    deep_files <- sort(list.files(deep_dir, pattern = "(_error_hit|_fit_overlay)[.]png$", full.names = TRUE))
  }
  for (path in deep_files) {
    priority <- if (grepl("_error_hit[.]png$", path)) "deep_error_hit" else "deep_fit_overlay"
    stage_rows <- add_figure(stage_rows, "03_deep_mcmc_reference", priority, path)
  }

  wide_manifest <- read_manifest(wide_dir)
  if (!is.null(wide_manifest)) {
    wide_files <- file.path(wide_dir, wide_manifest$relative_path)
  } else {
    wide_files <- sort(list.files(wide_dir, pattern = "[.]png$", full.names = TRUE))
  }
  for (path in wide_files) {
    priority <- if (grepl("_elbo_trace[.]png$", path)) {
      "wide_elbo"
    } else if (grepl("_fit_overlay[.]png$", path)) {
      "wide_fit_overlay"
    } else {
      "wide_mcmc_traces"
    }
    stage_rows <- add_figure(stage_rows, "04_wide_reference_temp_diagnostics", priority, path)
  }

  if (!length(stage_rows)) stop("No figures were selected for review.", call. = FALSE)
  selected <- do.call(rbind, stage_rows)
  selected$source_path <- normalizePath(selected$source_path, mustWork = FALSE)
  missing <- selected$source_path[!file.exists(selected$source_path)]
  if (length(missing)) {
    stop(sprintf("Missing figure source(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  root <- tryCatch(app_repo_root(), error = function(e) normalizePath(".", mustWork = TRUE))
  index_rows <- vector("list", nrow(selected))
  for (ii in seq_len(nrow(selected))) {
    src <- selected$source_path[[ii]]
    src_rel <- sub(paste0("^", regex_escape(root), "/?"), "", src)
    review_filename <- sprintf(
      "%02d_%s__%s",
      ii,
      selected$stage[[ii]],
      basename(src)
    )
    dest <- file.path(out_dir, review_filename)
    ok <- file.copy(src, dest, overwrite = TRUE)
    if (!ok) stop(sprintf("Failed to copy figure: %s", src), call. = FALSE)
    index_rows[[ii]] <- data.frame(
      stage = selected$stage[[ii]],
      priority = selected$priority[[ii]],
      review_filename = review_filename,
      source_path = src_rel,
      size_bytes = as.numeric(file.info(dest)$size),
      sha256 = app_sha256_file(dest),
      stringsAsFactors = FALSE
    )
  }
  figure_index <- do.call(rbind, index_rows)
  figure_index_path <- app_joint_qvp_write_csv(figure_index, file.path(out_dir, "figure_review_index.csv"))

  generated <- format(generated_time, "%Y-%m-%d %H:%M:%S %Z")
  readme <- c(
    "# Joint QVP Diagnostic Figure Review",
    "",
    sprintf("Generated: %s", generated),
    sprintf("Figure count: %d", nrow(figure_index)),
    "",
    "Open `index.html` to browse all copied figures in one place.",
    "",
    "Included groups:",
    "- toy fit validation: overlay, error/hit, ELBO, parameter traces;",
    "- suite fit validation: overlay and error/hit for all six scenarios;",
    "- deep MCMC reference: overlay and error/hit for selected targets;",
    "- wide/reference temporary diagnostics: ELBO, overlay, and parameter traces."
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(readme, readme_path)
  readme_path <- normalizePath(readme_path, mustWork = TRUE)

  html_blocks <- unlist(lapply(seq_len(nrow(figure_index)), function(ii) {
    row <- figure_index[ii, , drop = FALSE]
    c(
      "<section>",
      sprintf("<h2>%02d. %s</h2>", ii, html_escape(row$review_filename)),
      sprintf(
        "<p><strong>%s</strong> / %s<br><code>%s</code><br><code>%s</code></p>",
        html_escape(row$stage),
        html_escape(row$priority),
        html_escape(row$source_path),
        html_escape(row$sha256)
      ),
      sprintf("<img src=\"%s\" alt=\"%s\">", html_escape(row$review_filename), html_escape(row$review_filename)),
      "</section>"
    )
  }), use.names = FALSE)
  html <- c(
    "<!doctype html>",
    "<html lang=\"en\">",
    "<head>",
    "<meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>Joint QVP Diagnostic Figure Review</title>",
    "<style>",
    "body{font-family:Arial,sans-serif;margin:24px;background:#f7f7f4;color:#1f2328;}",
    "main{max-width:1280px;margin:0 auto;}",
    "section{margin:28px 0;padding-bottom:28px;border-bottom:1px solid #d8d8d2;}",
    "h1{font-size:28px;margin-bottom:4px;}h2{font-size:18px;margin-bottom:8px;}",
    "p{font-size:13px;line-height:1.45;color:#3f454d;}code{font-size:12px;}",
    "img{display:block;width:100%;height:auto;background:white;border:1px solid #d8d8d2;}",
    "</style>",
    "</head>",
    "<body><main>",
    "<h1>Joint QVP Diagnostic Figure Review</h1>",
    sprintf("<p>Generated %s. Figure count: %d.</p>", html_escape(generated), nrow(figure_index)),
    html_blocks,
    "</main></body></html>"
  )
  html_path <- file.path(out_dir, "index.html")
  writeLines(html, html_path)
  html_path <- normalizePath(html_path, mustWork = TRUE)

  artifact_paths <- c(
    figure_review_index = figure_index_path,
    readme = readme_path,
    index_html = html_path,
    setNames(file.path(out_dir, figure_index$review_filename), paste0("figure_", seq_len(nrow(figure_index))))
  )
  artifact_manifest <- data.frame(
    label = names(artifact_paths),
    relative_path = basename(artifact_paths),
    size_bytes = as.numeric(file.info(artifact_paths)$size),
    sha256 = vapply(artifact_paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  artifact_manifest_path <- app_joint_qvp_write_csv(artifact_manifest, file.path(out_dir, "artifact_manifest.csv"))

  list(
    out_dir = out_dir,
    paths = c(
      figure_review_index = figure_index_path,
      readme = readme_path,
      index_html = html_path,
      artifact_manifest = artifact_manifest_path
    ),
    figure_index = figure_index,
    artifact_manifest = artifact_manifest
  )
}

app_joint_qvp_run_ts_vb_convergence_audit <- function(
  out_dir,
  calibration_dir,
  max_iter_grid = c(240L, 360L, 500L),
  review_only = TRUE,
  vb_tol = 1.0e-4,
  kappa = NULL,
  tau0 = NULL,
  a_sigma = NULL,
  b_sigma = NULL,
  alpha_prior_mean = NULL,
  alpha_prior_sd = NULL,
  rhs_vb_inner = NULL
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  calibration_dir <- normalizePath(calibration_dir, mustWork = TRUE)
  assessment_path <- file.path(calibration_dir, "replicated_assessment.csv")
  run_config_path <- file.path(calibration_dir, "replicated_run_config.csv")
  if (!file.exists(assessment_path) || !file.exists(run_config_path)) {
    stop("calibration_dir must contain replicated_assessment.csv and replicated_run_config.csv.", call. = FALSE)
  }
  assessment <- utils::read.csv(assessment_path, stringsAsFactors = FALSE)
  run_config <- utils::read.csv(run_config_path, stringsAsFactors = FALSE)
  if (!"case_id" %in% names(assessment) || !"case_id" %in% names(run_config)) {
    stop("Convergence audit inputs must contain case_id columns.", call. = FALSE)
  }
  selected_ids <- if (isTRUE(review_only) && "implementation_status" %in% names(assessment)) {
    assessment$case_id[assessment$implementation_status == "review"]
  } else {
    assessment$case_id
  }
  selected_ids <- unique(as.character(selected_ids[nzchar(selected_ids)]))
  selected <- run_config[run_config$case_id %in% selected_ids, , drop = FALSE]
  selected <- selected[match(selected_ids, selected$case_id), , drop = FALSE]
  selected <- selected[!is.na(selected$case_id), , drop = FALSE]
  if (!nrow(selected)) stop("No convergence-audit cases selected.", call. = FALSE)
  max_iter_grid <- sort(unique(as.integer(max_iter_grid)))
  max_iter_grid <- max_iter_grid[is.finite(max_iter_grid) & max_iter_grid > 0L]
  if (!length(max_iter_grid)) stop("max_iter_grid must contain positive integers.", call. = FALSE)

  get_cell <- function(sc, name, default) {
    value <- if (name %in% names(sc)) sc[[name]][[1L]] else default
    if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) default else value
  }
  probe_rows <- list()
  for (ii in seq_len(nrow(selected))) {
    sc <- selected[ii, , drop = FALSE]
    fixture <- app_joint_qvp_ts_fixture_from_scenario(sc)
    sc_kappa <- as.numeric(kappa %||% get_cell(sc, "kappa", 1))
    sc_tau0 <- as.numeric(tau0 %||% get_cell(sc, "tau0", 1))
    sc_a_sigma <- as.numeric(a_sigma %||% get_cell(sc, "a_sigma", 2))
    sc_b_sigma <- as.numeric(b_sigma %||% get_cell(sc, "b_sigma", 1))
    sc_alpha_prior_mean <- alpha_prior_mean %||% get_cell(sc, "alpha_prior_mean", "empirical_quantile")
    sc_alpha_prior_sd <- as.numeric(alpha_prior_sd %||% get_cell(sc, "alpha_prior_sd", 1))
    sc_rhs_vb_inner <- as.integer(rhs_vb_inner %||% get_cell(sc, "rhs_vb_inner", 5L))
    for (max_iter in max_iter_grid) {
      fit <- app_joint_qvp_fit_al_vb_tiny(
        y = fixture$y,
        Z = fixture$Z,
        tau = fixture$tau,
        max_iter = max_iter,
        tol = vb_tol,
        kappa = sc_kappa,
        tau0 = sc_tau0,
        a_sigma = sc_a_sigma,
        b_sigma = sc_b_sigma,
        alpha_prior_mean = sc_alpha_prior_mean,
        alpha_prior_sd = sc_alpha_prior_sd,
        rhs_vb_inner = sc_rhs_vb_inner
      )
      hit <- vapply(seq_along(fixture$tau), function(k) mean(fixture$y <= fit$qhat_mean[, k]), numeric(1L))
      probe_rows[[length(probe_rows) + 1L]] <- data.frame(
        case_id = as.character(sc$case_id[[1L]]),
        base_case_id = as.character(get_cell(sc, "base_case_id", sc$case_id[[1L]])),
        replicate_id = as.integer(get_cell(sc, "replicate_id", NA_integer_)),
        calibration_seed = as.integer(get_cell(sc, "seed", NA_integer_)),
        max_iter = as.integer(max_iter),
        converged = isTRUE(fit$converged),
        n_iter = nrow(fit$trace),
        final_max_beta_change = tail(fit$trace$max_beta_change, 1L),
        objective_status = fit$objective_diagnostics$objective_status[[1L]],
        qhat_truth_normalized_distance = app_joint_qvp_qhat_truth_distance(fixture, fit$qhat_mean),
        max_abs_hit_rate_error = max(abs(hit - fixture$tau)),
        kappa = sc_kappa,
        tau0 = sc_tau0,
        alpha_prior_mean = paste(as.character(sc_alpha_prior_mean), collapse = ","),
        alpha_prior_sd = sc_alpha_prior_sd,
        rhs_vb_inner = sc_rhs_vb_inner,
        stringsAsFactors = FALSE
      )
      if (isTRUE(fit$converged)) break
    }
  }
  probe <- app_bind_rows_fill(probe_rows)
  final <- app_bind_rows_fill(lapply(split(probe, probe$case_id), function(x) x[nrow(x), , drop = FALSE]))
  final$resolution_status <- ifelse(final$converged, "resolved_by_iteration_grid", "still_max_iter")
  final <- final[order(final$resolution_status, final$base_case_id, final$case_id), , drop = FALSE]
  summary <- data.frame(
    metric = c(
      "selected_cases",
      "resolved_cases",
      "unresolved_cases",
      "max_grid_iter",
      "max_final_qhat_truth_distance",
      "max_final_abs_hit_rate_error"
    ),
    value = c(
      nrow(final),
      sum(final$converged),
      sum(!final$converged),
      max(max_iter_grid),
      max(final$qhat_truth_normalized_distance, na.rm = TRUE),
      max(final$max_abs_hit_rate_error, na.rm = TRUE)
    ),
    stringsAsFactors = FALSE
  )
  report <- c(
    "# Joint-QVP Time-Series VB Convergence Audit",
    "",
    "Date: 2026-07-02",
    "",
    "## Purpose",
    "",
    "Audit whether regenerated `kappa = 1` implementation-review rows are substantive fit failures or short-iteration convergence-cap reviews.",
    "",
    "## Result",
    "",
    sprintf("- Selected implementation-review cases: %d.", nrow(final)),
    sprintf("- Resolved by the tested iteration grid: %d.", sum(final$converged)),
    sprintf("- Still at max_iter after the tested grid: %d.", sum(!final$converged)),
    sprintf("- Maximum tested VB iteration cap: %d.", max(max_iter_grid)),
    sprintf("- Maximum final normalized truth distance: %.3f.", max(final$qhat_truth_normalized_distance, na.rm = TRUE)),
    sprintf("- Maximum final absolute hit-rate error: %.3f.", max(final$max_abs_hit_rate_error, na.rm = TRUE)),
    "",
    "## Interpretation",
    "",
    "Rows that converge at a higher iteration cap should be treated as default-control calibration issues. Rows that remain unconverged but retain good truth and hit diagnostics should stay as implementation-review rows until a better convergence or stopping policy is adopted."
  )
  paths <- c(
    convergence_probe = app_joint_qvp_write_csv(probe, file.path(out_dir, "convergence_probe.csv")),
    case_resolution_summary = app_joint_qvp_write_csv(final, file.path(out_dir, "case_resolution_summary.csv")),
    audit_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "audit_summary.csv"))
  )
  report_path <- file.path(out_dir, "audit_report.md")
  writeLines(report, report_path)
  paths <- c(paths, audit_report = normalizePath(report_path, mustWork = TRUE))
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = out_dir,
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    convergence_probe = probe,
    case_resolution_summary = final,
    audit_summary = summary
  )
}

app_joint_qvp_repo_provenance <- function() {
  root <- tryCatch(app_repo_root(), error = function(e) getwd())
  git <- function(args) {
    tryCatch(
      system2("git", args, cwd = root, stdout = TRUE, stderr = FALSE),
      error = function(e) NA_character_
    )[[1L]]
  }
  list(
    repo_root = root,
    branch = git(c("branch", "--show-current")),
    commit = git(c("rev-parse", "HEAD")),
    r_version = R.version.string
  )
}

app_joint_qvp_manifest_row <- function(
  fit_id,
  tau,
  kappa,
  likelihood,
  inference,
  seed = NA_integer_,
  status = "prototype"
) {
  prov <- app_joint_qvp_repo_provenance()
  data.frame(
    fit_id = fit_id,
    likelihood = likelihood,
    inference = inference,
    quantile_grid = paste(format(app_joint_qvp_validate_tau_grid(tau), digits = 8), collapse = ","),
    kappa = as.numeric(kappa),
    seed = as.integer(seed),
    status = status,
    repo_branch = prov$branch %||% NA_character_,
    repo_commit = prov$commit %||% NA_character_,
    r_version = prov$r_version,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_rinvgamma <- function(n, shape, rate) {
  shape <- rep(as.numeric(shape), length.out = n)
  rate <- rep(as.numeric(rate), length.out = n)
  if (any(!is.finite(shape)) || any(shape <= 0) || any(!is.finite(rate)) || any(rate <= 0)) {
    stop("Inverse-gamma shape/rate must be positive and finite.", call. = FALSE)
  }
  1 / stats::rgamma(n, shape = shape, rate = rate)
}

app_joint_qvp_rinvgauss <- function(n, mu, lambda) {
  if (any(!is.finite(mu)) || any(mu <= 0) || any(!is.finite(lambda)) || any(lambda <= 0)) {
    stop("Inverse-Gaussian parameters must be positive.", call. = FALSE)
  }
  mu <- rep(mu, length.out = n)
  lambda <- rep(lambda, length.out = n)
  out <- numeric(n)
  for (i in seq_len(n)) {
    y <- stats::rnorm(1)^2
    x <- mu[[i]] + (mu[[i]]^2 * y) / (2 * lambda[[i]]) -
      (mu[[i]] / (2 * lambda[[i]])) * sqrt(4 * mu[[i]] * lambda[[i]] * y + mu[[i]]^2 * y^2)
    u <- stats::runif(1)
    out[[i]] <- if (u <= mu[[i]] / (mu[[i]] + x)) x else mu[[i]]^2 / x
  }
  out
}

app_joint_qvp_rgig_half <- function(chi, psi) {
  chi <- pmin(pmax(as.numeric(chi), .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(as.numeric(psi), .Machine$double.eps), 1.0e100)
  y <- app_joint_qvp_rinvgauss(length(chi), mu = sqrt(psi / chi), lambda = psi)
  1 / y
}

app_joint_qvp_rgig_log_slice_one <- function(lambda, chi, psi, x0 = NULL, width = 1, max_steps = 100L) {
  if (!is.finite(lambda) || !is.finite(chi) || chi < 0 || !is.finite(psi) || psi <= 0) {
    stop("GIG log-slice parameters are invalid.", call. = FALSE)
  }
  chi <- pmin(pmax(chi, .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(psi, .Machine$double.eps), 1.0e100)
  log_density <- function(x) {
    lambda * x - 0.5 * (chi * exp(-x) + psi * exp(x))
  }
  mode <- log((lambda + sqrt(lambda^2 + chi * psi)) / psi)
  x0 <- as.numeric(x0 %||% mode)[[1L]]
  if (!is.finite(x0)) x0 <- mode
  y_level <- log_density(x0) - stats::rexp(1)
  left <- x0 - stats::runif(1, 0, width)
  right <- left + width
  j <- floor(stats::runif(1, 0, max_steps))
  k <- (max_steps - 1L) - j
  while (j > 0L && log_density(left) > y_level) {
    left <- left - width
    j <- j - 1L
  }
  while (k > 0L && log_density(right) > y_level) {
    right <- right + width
    k <- k - 1L
  }
  repeat {
    x_new <- stats::runif(1, left, right)
    if (log_density(x_new) >= y_level) return(exp(x_new))
    if (x_new < x0) left <- x_new else right <- x_new
  }
}

app_joint_qvp_rgig <- function(lambda, chi, psi, current = NULL) {
  chi <- pmin(pmax(as.numeric(chi), .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(as.numeric(psi), .Machine$double.eps), 1.0e100)
  n <- length(chi)
  lambda <- rep(as.numeric(lambda), length.out = n)
  psi <- rep(psi, length.out = n)
  current <- if (is.null(current)) rep(NA_real_, n) else rep(as.numeric(current), length.out = n)
  if (any(!is.finite(lambda)) || any(!is.finite(chi)) || any(chi < 0) ||
      any(!is.finite(psi)) || any(psi <= 0)) {
    stop("GIG parameters must be finite with chi >= 0 and psi > 0.", call. = FALSE)
  }
  out <- numeric(n)
  for (ii in seq_len(n)) {
    out[[ii]] <- app_joint_qvp_rgig_log_slice_one(
      lambda = lambda[[ii]],
      chi = chi[[ii]],
      psi = psi[[ii]],
      x0 = if (is.finite(current[[ii]]) && current[[ii]] > 0) log(current[[ii]]) else NULL
    )
  }
  out
}

app_joint_qvp_gig_log_mode_one <- function(lambda, chi, psi) {
  root <- sqrt(lambda^2 + chi * psi)
  mode <- if (lambda >= 0) {
    log((lambda + root) / psi)
  } else {
    log(chi / (root - lambda))
  }
  if (!is.finite(mode)) mode <- 0.5 * (log(chi) - log(psi))
  if (!is.finite(mode)) stop("Could not compute GIG log-kernel mode.", call. = FALSE)
  mode
}

app_joint_qvp_gig_log_kernel_u <- function(u, lambda, chi, psi) {
  log_max <- log(.Machine$double.xmax)
  log_min <- log(.Machine$double.xmin)
  log_chi_term <- log(chi) - u
  log_psi_term <- log(psi) + u
  chi_term <- ifelse(log_chi_term > log_max, Inf, ifelse(log_chi_term < log_min, 0, exp(log_chi_term)))
  psi_term <- ifelse(log_psi_term > log_max, Inf, ifelse(log_psi_term < log_min, 0, exp(log_psi_term)))
  out <- lambda * u - 0.5 * (chi_term + psi_term)
  out[!is.finite(chi_term) | !is.finite(psi_term)] <- -Inf
  out
}

app_joint_qvp_gig_log_integral_numeric_one <- function(lambda, chi, psi) {
  mode <- app_joint_qvp_gig_log_mode_one(lambda, chi, psi)
  f_mode <- app_joint_qvp_gig_log_kernel_u(mode, lambda, chi, psi)
  if (!is.finite(f_mode)) return(NA_real_)
  curvature <- 0.5 * (
    exp(pmin(log(chi) - mode, log(.Machine$double.xmax))) +
      exp(pmin(log(psi) + mode, log(.Machine$double.xmax)))
  )
  scale <- 1 / sqrt(pmax(curvature, .Machine$double.eps))
  scale <- pmin(pmax(scale, 1.0e-8), 50)
  integrand <- function(t) {
    u <- mode + scale * t
    log_val <- app_joint_qvp_gig_log_kernel_u(u, lambda, chi, psi) - f_mode
    out <- scale * exp(pmin(log_val, 0))
    out[!is.finite(out)] <- 0
    out
  }
  val <- stats::integrate(
    integrand,
    lower = -80,
    upper = 80,
    subdivisions = 500L,
    rel.tol = 1.0e-10,
    stop.on.error = FALSE
  )
  if (!is.finite(val$value) || val$value <= 0) {
    integrand_u <- function(u) {
      log_val <- app_joint_qvp_gig_log_kernel_u(u, lambda, chi, psi) - f_mode
      out <- exp(pmin(log_val, 0))
      out[!is.finite(out)] <- 0
      out
    }
    val <- stats::integrate(
      integrand_u,
      lower = -Inf,
      upper = Inf,
      subdivisions = 500L,
      rel.tol = 1.0e-10,
      stop.on.error = FALSE
    )
  }
  if (!is.finite(val$value) || val$value <= 0) return(NA_real_)
  f_mode + log(val$value)
}

app_joint_qvp_gig_log_integral <- function(lambda, chi, psi) {
  n <- max(length(lambda), length(chi), length(psi))
  lambda <- rep(as.numeric(lambda), length.out = n)
  chi <- pmin(pmax(rep(as.numeric(chi), length.out = n), .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(rep(as.numeric(psi), length.out = n), .Machine$double.eps), 1.0e100)
  if (any(!is.finite(lambda)) || any(!is.finite(chi)) || any(!is.finite(psi))) {
    stop("GIG log-integral parameters must be finite.", call. = FALSE)
  }
  z <- sqrt(chi * psi)
  scaled_k <- besselK(z, nu = lambda, expon.scaled = TRUE)
  out <- log(2) + log(scaled_k) - z + 0.5 * lambda * (log(chi) - log(psi))
  if (any(!is.finite(out))) {
    bad <- which(!is.finite(out))
    for (i in bad) {
      out[[i]] <- app_joint_qvp_gig_log_integral_numeric_one(lambda[[i]], chi[[i]], psi[[i]])
    }
  }
  if (any(!is.finite(out))) stop("Could not compute GIG log normalizing integral.", call. = FALSE)
  out
}

app_joint_qvp_gig_moment_numeric_one <- function(lambda, chi, psi, r) {
  log_num <- app_joint_qvp_gig_log_integral_numeric_one(lambda + r, chi, psi)
  log_den <- app_joint_qvp_gig_log_integral_numeric_one(lambda, chi, psi)
  log_out <- log_num - log_den
  if (is.finite(log_out) && log_out > log(.Machine$double.xmax)) return(.Machine$double.xmax)
  if (is.finite(log_out) && log_out < log(.Machine$double.xmin)) return(.Machine$double.xmin)
  out <- exp(log_out)
  if (!is.finite(out)) stop("Could not compute deterministic GIG moment.", call. = FALSE)
  out
}

app_joint_qvp_gig_moment <- function(lambda, chi, psi, r) {
  n <- max(length(lambda), length(chi), length(psi))
  lambda <- rep(as.numeric(lambda), length.out = n)
  chi <- pmin(pmax(rep(as.numeric(chi), length.out = n), .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(rep(as.numeric(psi), length.out = n), .Machine$double.eps), 1.0e100)
  r <- as.numeric(r)[[1L]]
  z <- sqrt(chi * psi)
  num <- besselK(z, nu = lambda + r, expon.scaled = TRUE)
  den <- besselK(z, nu = lambda, expon.scaled = TRUE)
  out <- (num / den) * (chi / psi)^(r / 2)
  if (any(!is.finite(out) | out <= 0)) {
    bad <- which(!is.finite(out) | out <= 0)
    for (i in bad) {
      out[[i]] <- app_joint_qvp_gig_moment_numeric_one(lambda[[i]], chi[[i]], psi[[i]], r)
    }
  }
  if (any(!is.finite(out) | out <= 0)) stop("Could not compute deterministic GIG moment.", call. = FALSE)
  out
}

app_joint_qvp_gig_log_moment <- function(lambda, chi, psi) {
  n <- max(length(lambda), length(chi), length(psi))
  lambda <- rep(as.numeric(lambda), length.out = n)
  chi <- pmin(pmax(rep(as.numeric(chi), length.out = n), .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(rep(as.numeric(psi), length.out = n), .Machine$double.eps), 1.0e100)
  h <- 1.0e-4 * pmax(1, abs(lambda))
  out <- (app_joint_qvp_gig_log_integral(lambda + h, chi, psi) -
    app_joint_qvp_gig_log_integral(lambda - h, chi, psi)) / (2 * h)
  if (any(!is.finite(out))) stop("Could not compute GIG E[log X].", call. = FALSE)
  out
}

app_joint_qvp_gig_entropy <- function(lambda, chi, psi, mean = NULL, inv_mean = NULL, log_mean = NULL) {
  n <- max(length(lambda), length(chi), length(psi))
  lambda <- rep(as.numeric(lambda), length.out = n)
  chi <- pmin(pmax(rep(as.numeric(chi), length.out = n), .Machine$double.eps), 1.0e100)
  psi <- pmin(pmax(rep(as.numeric(psi), length.out = n), .Machine$double.eps), 1.0e100)
  mean <- as.numeric(mean %||% app_joint_qvp_gig_moment(lambda, chi, psi, 1))
  inv_mean <- as.numeric(inv_mean %||% app_joint_qvp_gig_moment(lambda, chi, psi, -1))
  log_mean <- as.numeric(log_mean %||% app_joint_qvp_gig_log_moment(lambda, chi, psi))
  mean <- rep(mean, length.out = n)
  inv_mean <- rep(inv_mean, length.out = n)
  log_mean <- rep(log_mean, length.out = n)
  out <- app_joint_qvp_gig_log_integral(lambda, chi, psi) -
    (lambda - 1) * log_mean + 0.5 * chi * inv_mean + 0.5 * psi * mean
  if (any(!is.finite(out))) stop("Could not compute GIG entropy.", call. = FALSE)
  out
}

app_joint_qvp_slice_bounded_one <- function(x0, lower, upper, log_density, width = NULL, max_steps = 100L) {
  if (!is.finite(lower) || !is.finite(upper) || lower >= upper) {
    stop("Bounded slice sampler requires finite increasing bounds.", call. = FALSE)
  }
  x0 <- as.numeric(x0)[[1L]]
  if (!is.finite(x0) || x0 <= lower || x0 >= upper) x0 <- (lower + upper) / 2
  f0 <- log_density(x0)
  if (!is.finite(f0)) x0 <- (lower + upper) / 2
  f0 <- log_density(x0)
  if (!is.finite(f0)) stop("Bounded slice sampler could not find a finite starting density.", call. = FALSE)
  width <- as.numeric(width %||% ((upper - lower) / 10))[[1L]]
  width <- min(max(width, .Machine$double.eps), upper - lower)
  y_level <- f0 - stats::rexp(1)
  left <- max(lower, x0 - stats::runif(1, 0, width))
  right <- min(upper, left + width)
  j <- floor(stats::runif(1, 0, max_steps))
  k <- (max_steps - 1L) - j
  while (j > 0L && left > lower && log_density(left) > y_level) {
    left <- max(lower, left - width)
    j <- j - 1L
  }
  while (k > 0L && right < upper && log_density(right) > y_level) {
    right <- min(upper, right + width)
    k <- k - 1L
  }
  for (attempt in seq_len(1000L)) {
    x_new <- stats::runif(1, left, right)
    if (log_density(x_new) >= y_level) return(x_new)
    if (x_new < x0) left <- x_new else right <- x_new
  }
  stop("Bounded slice sampler failed to accept after 1000 shrinkage attempts.", call. = FALSE)
}

app_joint_qvp_rtruncnorm <- function(n, mean, sd, lower = -Inf, upper = Inf) {
  if (requireNamespace("truncnorm", quietly = TRUE)) {
    return(truncnorm::rtruncnorm(n, a = lower, b = upper, mean = mean, sd = sd))
  }
  lo <- stats::pnorm(lower, mean = mean, sd = sd)
  hi <- stats::pnorm(upper, mean = mean, sd = sd)
  stats::qnorm(stats::runif(n, lo, hi), mean = mean, sd = sd)
}

app_joint_qvp_initialize_rhs_state <- function(K, p, tau0 = 1, zeta2 = Inf) {
  make_block <- function() {
    list(
      lambda2 = rep(1, p),
      nu = rep(1, p),
      tau2 = tau0^2,
      xi = 1,
      tau0 = tau0,
      zeta2 = zeta2,
      a_zeta = 2,
      b_zeta = 4
    )
  }
  innovations <- if (K > 1L) {
    stats::setNames(replicate(K - 1L, make_block(), simplify = FALSE), paste0("delta_", 2:K))
  } else {
    list()
  }
  blocks <- c(list(anchor = make_block()), innovations)
  blocks
}

app_joint_qvp_rhs_state_to_prior <- function(rhs_state) {
  anchor <- rhs_state$anchor
  innovations <- rhs_state[names(rhs_state) != "anchor"]
  list(
    anchor = list(lambda2 = anchor$lambda2, tau2 = anchor$tau2, zeta2 = anchor$zeta2),
    innovations = lapply(innovations, function(x) list(lambda2 = x$lambda2, tau2 = x$tau2, zeta2 = x$zeta2))
  )
}

app_joint_qvp_update_rhs_block <- function(block, theta) {
  theta <- as.numeric(theta)
  p <- length(theta)
  block$lambda2 <- app_joint_qvp_rinvgamma(
    p,
    shape = 1,
    rate = 1 / block$nu + theta^2 / (2 * block$tau2)
  )
  block$nu <- app_joint_qvp_rinvgamma(p, shape = 1, rate = 1 + 1 / block$lambda2)
  block$tau2 <- app_joint_qvp_rinvgamma(
    1,
    shape = p / 2,
    rate = 1 / block$xi + 0.5 * sum(theta^2 / block$lambda2)
  )
  block$xi <- app_joint_qvp_rinvgamma(1, shape = 1, rate = 1 / (block$tau0^2) + 1 / block$tau2)
  if (is.finite(block$zeta2)) {
    block$zeta2 <- app_joint_qvp_rinvgamma(
      1,
      shape = block$a_zeta + p / 2,
      rate = block$b_zeta + 0.5 * sum(theta^2)
    )
  }
  block
}

app_joint_qvp_update_rhs_state <- function(rhs_state, beta, K, p) {
  eta <- app_joint_qvp_apply_difference(beta, K, p)
  rhs_state$anchor <- app_joint_qvp_update_rhs_block(rhs_state$anchor, eta[seq_len(p)])
  if (K > 1L) {
    for (k in 2:K) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      nm <- paste0("delta_", k)
      rhs_state[[nm]] <- app_joint_qvp_update_rhs_block(rhs_state[[nm]], eta[idx])
    }
  }
  rhs_state
}

app_joint_qvp_difference_moments <- function(beta_mean, beta_cov, K, p) {
  beta_mean <- as.numeric(beta_mean)
  beta_cov <- as.matrix(beta_cov)
  if (length(beta_mean) != K * p || !identical(dim(beta_cov), c(K * p, K * p))) {
    stop("beta moments have incompatible dimensions.", call. = FALSE)
  }
  H <- app_joint_qvp_build_difference_matrix(K, p)
  eta_mean <- as.numeric(H %*% beta_mean)
  eta_var <- rowSums((as.matrix(H) %*% beta_cov) * as.matrix(H))
  eta_second <- eta_mean^2 + pmax(eta_var, 0)
  list(mean = eta_mean, variance = eta_var, second = eta_second)
}

app_joint_qvp_update_rhs_vb_block <- function(block, theta_second, n_inner = 5L) {
  theta_second <- pmax(as.numeric(theta_second), .Machine$double.eps)
  p <- length(theta_second)
  n_inner <- as.integer(n_inner)
  if (p < 1L || n_inner < 1L) stop("Invalid RHS VB block update inputs.", call. = FALSE)
  inv_clip <- function(x) pmin(pmax(as.numeric(x), 1.0e-10), 1.0e10)
  lambda2_inv <- inv_clip(block$lambda2_inv_mean %||% (1 / rep(block$lambda2 %||% 1, length.out = p)))
  nu_inv <- inv_clip(block$nu_inv_mean %||% (1 / rep(block$nu %||% 1, length.out = p)))
  tau2_inv <- inv_clip(block$tau2_inv_mean %||% (1 / (block$tau2 %||% 1)))
  xi_inv <- inv_clip(block$xi_inv_mean %||% (1 / (block$xi %||% 1)))
  tau0 <- as.numeric(block$tau0 %||% 1)[[1L]]
  if (!is.finite(tau0) || tau0 <= 0) stop("tau0 must be positive.", call. = FALSE)
  zeta_finite <- is.finite(as.numeric(block$zeta2 %||% Inf)[[1L]])
  zeta_inv <- if (zeta_finite) inv_clip(block$zeta2_inv_mean %||% (1 / block$zeta2)) else 0
  for (ii in seq_len(n_inner)) {
    lambda2_rate <- inv_clip(nu_inv + 0.5 * theta_second * tau2_inv)
    lambda2_inv <- inv_clip(1 / lambda2_rate)
    nu_inv <- inv_clip(1 / (1 + lambda2_inv))
    tau2_rate <- inv_clip(xi_inv + 0.5 * sum(theta_second * lambda2_inv))
    tau2_shape <- p / 2
    tau2_inv <- inv_clip(tau2_shape / tau2_rate)
    xi_inv <- inv_clip(1 / (1 / tau0^2 + tau2_inv))
    if (zeta_finite) {
      zeta_shape <- as.numeric(block$a_zeta %||% 2)[[1L]] + p / 2
      zeta_rate <- as.numeric(block$b_zeta %||% 4)[[1L]] + 0.5 * sum(theta_second)
      zeta_inv <- inv_clip(zeta_shape / zeta_rate)
    }
  }
  block$lambda2 <- 1 / lambda2_inv
  block$nu <- 1 / nu_inv
  block$tau2 <- 1 / tau2_inv
  block$xi <- 1 / xi_inv
  block$zeta2 <- if (zeta_finite) 1 / zeta_inv else Inf
  block$lambda2_inv_mean <- lambda2_inv
  block$nu_inv_mean <- nu_inv
  block$tau2_inv_mean <- tau2_inv
  block$xi_inv_mean <- xi_inv
  block$zeta2_inv_mean <- zeta_inv
  block$theta_second_mean <- theta_second
  block
}

app_joint_qvp_update_rhs_vb_state <- function(rhs_state, beta_mean, beta_cov, K, p, n_inner = 5L) {
  moments <- app_joint_qvp_difference_moments(beta_mean, beta_cov, K, p)
  rhs_state$anchor <- app_joint_qvp_update_rhs_vb_block(
    rhs_state$anchor,
    moments$second[seq_len(p)],
    n_inner = n_inner
  )
  if (K > 1L) {
    for (k in 2:K) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      nm <- paste0("delta_", k)
      rhs_state[[nm]] <- app_joint_qvp_update_rhs_vb_block(
        rhs_state[[nm]],
        moments$second[idx],
        n_inner = n_inner
      )
    }
  }
  list(state = rhs_state, moments = moments)
}

app_joint_qvp_rhs_vb_summary <- function(rhs_state, K, p) {
  prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
  prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
  rows <- lapply(names(prior$block_precisions), function(nm) {
    prec <- as.numeric(prior$block_precisions[[nm]])
    data.frame(
      block = nm,
      min_precision = min(prec),
      mean_precision = mean(prec),
      max_precision = max(prec),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_beta_prior_quadratic <- function(beta_mean, beta_cov, P_beta) {
  P_dense <- as.matrix(P_beta)
  as.numeric(crossprod(beta_mean, P_dense %*% beta_mean) + sum(P_dense * beta_cov))
}

app_joint_qvp_beta_logdet <- function(beta_cov) {
  det_val <- determinant(as.matrix(beta_cov), logarithm = TRUE)
  if (det_val$sign <= 0) return(NA_real_)
  as.numeric(det_val$modulus)
}

app_joint_qvp_monitor_row <- function(iter, terms) {
  term_names <- names(terms)
  terms <- as.numeric(terms)
  term_names <- term_names %||% paste0("term_", seq_along(terms))
  data.frame(
    iter = iter,
    term = term_names,
    value = terms,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_inv_gamma_entropy <- function(shape, rate) {
  shape <- as.numeric(shape)
  rate <- as.numeric(rate)
  if (length(shape) != length(rate) || any(!is.finite(shape)) ||
      any(!is.finite(rate)) || any(shape <= 0) || any(rate <= 0)) {
    stop("Inverse-gamma entropy inputs must be positive and finite.", call. = FALSE)
  }
  shape + log(rate) + lgamma(shape) - (1 + shape) * digamma(shape)
}

app_joint_qvp_inv_gamma_log_mean <- function(shape, rate) {
  shape <- as.numeric(shape)
  rate <- as.numeric(rate)
  if (length(shape) != length(rate) || any(!is.finite(shape)) ||
      any(!is.finite(rate)) || any(shape <= 0) || any(rate <= 0)) {
    stop("Inverse-gamma log-moment inputs must be positive and finite.", call. = FALSE)
  }
  log(rate) - digamma(shape)
}

app_joint_qvp_rhs_vb_block_accounting <- function(block, p) {
  p <- as.integer(p)
  if (p <= 0L) stop("RHS accounting requires p > 0.", call. = FALSE)
  inv_clip <- function(x) pmin(pmax(as.numeric(x), 1.0e-10), 1.0e10)
  lambda2_inv <- inv_clip(block$lambda2_inv_mean %||% (1 / rep(block$lambda2 %||% 1, length.out = p)))
  nu_inv <- inv_clip(block$nu_inv_mean %||% (1 / rep(block$nu %||% 1, length.out = p)))
  tau2_inv <- inv_clip(block$tau2_inv_mean %||% (1 / (block$tau2 %||% 1)))
  xi_inv <- inv_clip(block$xi_inv_mean %||% (1 / (block$xi %||% 1)))
  zeta_finite <- is.finite(as.numeric(block$zeta2 %||% Inf)[[1L]])
  zeta_inv <- if (zeta_finite) inv_clip(block$zeta2_inv_mean %||% (1 / block$zeta2)) else 0
  lambda_shape <- rep(1, p)
  lambda_rate <- lambda_shape / lambda2_inv
  nu_shape <- rep(1, p)
  nu_rate <- nu_shape / nu_inv
  tau_shape <- p / 2
  tau_rate <- tau_shape / tau2_inv
  xi_shape <- 1
  xi_rate <- xi_shape / xi_inv
  a_lambda <- 0.5
  a_nu <- 0.5
  a_tau <- 0
  tau0 <- as.numeric(block$tau0 %||% 1)[[1L]]
  if (!is.finite(tau0) || tau0 <= 0) stop("RHS accounting tau0 must be positive.", call. = FALSE)
  a_xi <- 1
  xi_prior_rate <- 1 / tau0^2
  elog_lambda <- app_joint_qvp_inv_gamma_log_mean(lambda_shape, lambda_rate)
  elog_nu <- app_joint_qvp_inv_gamma_log_mean(nu_shape, nu_rate)
  elog_tau <- app_joint_qvp_inv_gamma_log_mean(tau_shape, tau_rate)
  elog_xi <- app_joint_qvp_inv_gamma_log_mean(xi_shape, xi_rate)
  scale_prior <- sum(
    a_lambda * (-elog_nu) - lgamma(a_lambda) -
      (a_lambda + 1) * elog_lambda - nu_inv * lambda2_inv
  )
  scale_prior <- scale_prior + sum(
    -lgamma(a_nu) - (a_nu + 1) * elog_nu - nu_inv
  )
  scale_prior <- scale_prior + (-(a_tau + 1) * elog_tau - xi_inv * tau2_inv)
  scale_prior <- scale_prior +
    a_xi * log(xi_prior_rate) - lgamma(a_xi) -
      (a_xi + 1) * elog_xi - xi_prior_rate * xi_inv
  entropy <- sum(app_joint_qvp_inv_gamma_entropy(lambda_shape, lambda_rate)) +
    sum(app_joint_qvp_inv_gamma_entropy(nu_shape, nu_rate)) +
    app_joint_qvp_inv_gamma_entropy(tau_shape, tau_rate) +
    app_joint_qvp_inv_gamma_entropy(xi_shape, xi_rate)
  if (zeta_finite) {
    a_zeta <- as.numeric(block$a_zeta %||% 2)[[1L]]
    b_zeta <- as.numeric(block$b_zeta %||% 4)[[1L]]
    zeta_shape <- a_zeta + p / 2
    zeta_rate <- zeta_shape / zeta_inv
    elog_zeta <- app_joint_qvp_inv_gamma_log_mean(zeta_shape, zeta_rate)
    scale_prior <- scale_prior +
      a_zeta * log(b_zeta) - lgamma(a_zeta) -
        (a_zeta + 1) * elog_zeta - b_zeta * zeta_inv
    entropy <- entropy + app_joint_qvp_inv_gamma_entropy(zeta_shape, zeta_rate)
  }
  mean_precision <- lambda2_inv * tau2_inv + zeta_inv
  list(
    expected_log_scale_prior_kernel = as.numeric(scale_prior),
    q_scale_entropy = as.numeric(entropy),
    log_precision_approx = 0.5 * sum(log(pmax(mean_precision, .Machine$double.eps)))
  )
}

app_joint_qvp_rhs_vb_elbo_terms <- function(rhs_state, K, p) {
  block_names <- c("anchor", if (K > 1L) paste0("delta_", 2:K) else character())
  rows <- lapply(block_names, function(nm) {
    block_terms <- app_joint_qvp_rhs_vb_block_accounting(rhs_state[[nm]], p)
    data.frame(
      block = nm,
      term = c(
        "expected_log_rhs_scale_prior_kernel",
        "q_rhs_scale_entropy",
        "expected_log_beta_prior_log_precision_approx"
      ),
      value = c(
        block_terms$expected_log_scale_prior_kernel,
        block_terms$q_scale_entropy,
        block_terms$log_precision_approx
      ),
      status = c(
        "included_rhs_mean_field_implemented_convention",
        "included_rhs_mean_field_implemented_convention",
        "included_log_precision_mean_field_approximation"
      ),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  if (!all(is.finite(out$value))) stop("RHS ELBO accounting terms must be finite.", call. = FALSE)
  out
}

app_joint_qvp_al_vb_data_accounting <- function(
  y,
  Z,
  beta_mean,
  beta_cov,
  alpha,
  sigma_shape,
  sigma_rate,
  v_mean,
  v_inv_mean,
  constants,
  kappa
) {
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  beta_cov <- as.matrix(beta_cov)
  alpha <- as.numeric(alpha)
  sigma_shape <- as.numeric(sigma_shape)
  sigma_rate <- as.numeric(sigma_rate)
  v_mean <- as.matrix(v_mean)
  v_inv_mean <- as.matrix(v_inv_mean)
  K <- length(alpha)
  Tn <- length(y)
  p <- ncol(Z)
  if (length(beta_mean) != K * p || !identical(dim(beta_cov), c(K * p, K * p))) {
    stop("AL-VB accounting beta moments have incompatible dimensions.", call. = FALSE)
  }
  if (nrow(Z) != Tn || length(sigma_shape) != K || length(sigma_rate) != K ||
      !identical(dim(v_mean), c(Tn, K)) || !identical(dim(v_inv_mean), c(Tn, K))) {
    stop("AL-VB accounting inputs have incompatible dimensions.", call. = FALSE)
  }
  if (any(!is.finite(sigma_shape)) || any(!is.finite(sigma_rate)) ||
      any(sigma_shape <= 0) || any(sigma_rate <= 0)) {
    stop("AL-VB sigma accounting inputs must be positive and finite.", call. = FALSE)
  }
  sigma_inv <- sigma_shape / sigma_rate
  sigma_log <- log(sigma_rate) - digamma(sigma_shape)
  beta_mat <- app_joint_qvp_beta_matrix(beta_mean, K, p)
  fitted_no_alpha <- Z %*% beta_mat
  likelihood_quadratic <- 0
  latent_rate <- 0
  latent_log_kernel <- 0
  v_entropy <- 0
  lambda_v <- 1 - kappa / 2
  for (k in seq_len(K)) {
    idx_beta <- ((k - 1L) * p + 1L):(k * p)
    beta_var <- rowSums((Z %*% beta_cov[idx_beta, idx_beta, drop = FALSE]) * Z)
    r_mean <- y - alpha[[k]] - fitted_no_alpha[, k]
    r2_mean <- r_mean^2 + pmax(beta_var, 0)
    chi <- kappa * sigma_inv[[k]] * r2_mean / constants$B[[k]]
    psi <- kappa * sigma_inv[[k]] * (constants$A[[k]]^2 / constants$B[[k]] + 2)
    v_log_mean <- app_joint_qvp_gig_log_moment(lambda_v, chi, psi)
    residual_bracket <- sum(
      r2_mean * v_inv_mean[, k] -
        2 * constants$A[[k]] * r_mean +
        constants$A[[k]]^2 * v_mean[, k]
    )
    likelihood_quadratic <- likelihood_quadratic +
      0.5 * kappa * sigma_inv[[k]] / constants$B[[k]] * residual_bracket
    latent_rate <- latent_rate + kappa * sigma_inv[[k]] * sum(v_mean[, k])
    latent_log_kernel <- latent_log_kernel - 0.5 * kappa * sum(v_log_mean)
    v_entropy <- v_entropy + sum(app_joint_qvp_gig_entropy(
      lambda = lambda_v,
      chi = chi,
      psi = psi,
      mean = v_mean[, k],
      inv_mean = v_inv_mean[, k],
      log_mean = v_log_mean
    ))
  }
  list(
    likelihood_quadratic = likelihood_quadratic,
    latent_rate = latent_rate,
    expected_log_observation_quadratic_kernel = -likelihood_quadratic,
    expected_log_v_log_kernel = latent_log_kernel,
    expected_log_v_rate_kernel = -latent_rate,
    expected_log_sigma_power_kernel = -1.5 * kappa * Tn * sum(sigma_log),
    q_v_entropy = v_entropy,
    sigma_log_mean = sigma_log,
    sigma_inv_mean = sigma_inv
  )
}

app_joint_qvp_al_vb_partial_elbo_terms <- function(
  iter,
  data_terms,
  rhs_terms,
  prior_quadratic,
  beta_logdet,
  beta_dim,
  sigma_shape,
  sigma_rate,
  a_sigma,
  b_sigma
) {
  beta_dim <- as.integer(beta_dim)
  if (beta_dim <= 0L || !is.finite(beta_logdet)) {
    stop("AL-VB beta entropy accounting inputs are invalid.", call. = FALSE)
  }
  sigma_shape <- as.numeric(sigma_shape)
  sigma_rate <- as.numeric(sigma_rate)
  sigma_log <- log(sigma_rate) - digamma(sigma_shape)
  sigma_inv <- sigma_shape / sigma_rate
  sigma_prior_kernel <- sum(-(a_sigma + 1) * sigma_log - b_sigma * sigma_inv)
  rhs_terms <- rhs_terms %||% data.frame(term = character(), value = numeric(), status = character())
  rhs_value <- function(term) {
    idx <- which(rhs_terms$term == term)
    if (!length(idx)) return(NA_real_)
    sum(rhs_terms$value[idx])
  }
  included <- data.frame(
    iter = iter,
    term = c(
      "expected_log_observation_quadratic_kernel",
      "expected_log_v_log_kernel",
      "expected_log_v_rate_kernel",
      "expected_log_sigma_power_kernel",
      "expected_log_beta_prior_kernel",
      "expected_log_beta_prior_log_precision_approx",
      "expected_log_sigma_prior_kernel",
      "expected_log_rhs_scale_prior_kernel",
      "q_v_entropy",
      "q_beta_entropy",
      "q_sigma_entropy",
      "q_rhs_scale_entropy"
    ),
    value = c(
      data_terms$expected_log_observation_quadratic_kernel,
      data_terms$expected_log_v_log_kernel,
      data_terms$expected_log_v_rate_kernel,
      data_terms$expected_log_sigma_power_kernel,
      -prior_quadratic,
      rhs_value("expected_log_beta_prior_log_precision_approx"),
      sigma_prior_kernel,
      rhs_value("expected_log_rhs_scale_prior_kernel"),
      data_terms$q_v_entropy,
      0.5 * (beta_dim * (1 + log(2 * pi)) + beta_logdet),
      sum(app_joint_qvp_inv_gamma_entropy(sigma_shape, sigma_rate)),
      rhs_value("q_rhs_scale_entropy")
    ),
    included_in_partial_elbo = TRUE,
    status = c(
      rep("included_parameter_dependent_term", 5L),
      "included_log_precision_mean_field_approximation",
      "included_parameter_dependent_term",
      "included_rhs_mean_field_implemented_convention",
      rep("included_parameter_dependent_term", 3L),
      "included_rhs_mean_field_implemented_convention"
    ),
    stringsAsFactors = FALSE
  )
  missing <- data.frame(
    iter = iter,
    term = "alpha_point_mass_entropy",
    value = NA_real_,
    included_in_partial_elbo = FALSE,
    status = "point_intercept_approximation_no_density",
    stringsAsFactors = FALSE
  )
  out <- rbind(included, missing)
  if (!all(is.finite(out$value[out$included_in_partial_elbo]))) {
    stop("AL-VB partial ELBO included terms must be finite.", call. = FALSE)
  }
  out
}

app_joint_qvp_partial_elbo <- function(elbo_terms) {
  vals <- elbo_terms$value[elbo_terms$included_in_partial_elbo]
  if (!length(vals) || any(!is.finite(vals))) return(NA_real_)
  sum(vals)
}

app_joint_qvp_objective_diagnostics <- function(
  trace,
  value_col = "partial_elbo",
  objective_label = value_col,
  tolerance = 1.0e-8,
  approximation_status = "exact_or_accounted"
) {
  if (!is.data.frame(trace) || !nrow(trace) || !value_col %in% names(trace)) {
    return(data.frame(
      objective_label = objective_label,
      value_col = value_col,
      approximation_status = approximation_status,
      n_iter = if (is.data.frame(trace)) nrow(trace) else 0L,
      first_value = NA_real_,
      final_value = NA_real_,
      min_delta = NA_real_,
      max_drop = NA_real_,
      n_decreases = NA_integer_,
      tolerance = tolerance,
      all_finite = FALSE,
      monotone_within_tolerance = FALSE,
      objective_status = "not_available",
      stringsAsFactors = FALSE
    ))
  }
  vals <- as.numeric(trace[[value_col]])
  finite <- all(is.finite(vals))
  deltas <- if (length(vals) > 1L) diff(vals) else numeric()
  max_drop <- if (length(deltas)) max(pmax(-deltas, 0), na.rm = TRUE) else 0
  min_delta <- if (length(deltas)) min(deltas, na.rm = TRUE) else 0
  n_decreases <- if (length(deltas)) sum(deltas < -tolerance, na.rm = TRUE) else 0L
  monotone <- isTRUE(finite) && is.finite(max_drop) && max_drop <= tolerance
  status <- if (!finite || !is.finite(max_drop) || !is.finite(min_delta)) {
    "fail"
  } else if (monotone) {
    "pass"
  } else {
    "review"
  }
  data.frame(
    objective_label = objective_label,
    value_col = value_col,
    approximation_status = approximation_status,
    n_iter = length(vals),
    first_value = vals[[1L]],
    final_value = vals[[length(vals)]],
    min_delta = min_delta,
    max_drop = max_drop,
    n_decreases = n_decreases,
    tolerance = tolerance,
    all_finite = finite,
    monotone_within_tolerance = monotone,
    objective_status = status,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_normalize_init <- function(init, K, p) {
  if (is.null(init)) return(NULL)
  beta <- init$beta_mean %||% init$beta
  alpha <- init$alpha_mean %||% init$alpha
  sigma <- init$sigma_mean %||% init$sigma
  gamma <- init$gamma_mean %||% init$gamma %||% NULL
  out <- list()
  if (!is.null(beta)) {
    beta <- as.numeric(beta)
    if (length(beta) != K * p) stop("Initial beta has incompatible length.", call. = FALSE)
    out$beta <- beta
  }
  if (!is.null(alpha)) {
    alpha <- as.numeric(alpha)
    if (length(alpha) != K) stop("Initial alpha has incompatible length.", call. = FALSE)
    out$alpha <- sort(alpha)
  }
  if (!is.null(sigma)) {
    sigma <- as.numeric(sigma)
    if (length(sigma) != K || any(!is.finite(sigma)) || any(sigma <= 0)) {
      stop("Initial sigma must have length K and be positive.", call. = FALSE)
    }
    out$sigma <- sigma
  }
  if (!is.null(gamma)) {
    gamma <- as.numeric(gamma)
    if (length(gamma) != K) stop("Initial gamma has incompatible length.", call. = FALSE)
    out$gamma <- gamma
  }
  out
}

app_joint_qvp_alpha_prior_spec <- function(y, tau, alpha_prior_mean = NULL, alpha_prior_sd = Inf) {
  y <- as.numeric(y)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  K <- length(tau)
  if (is.null(alpha_prior_mean)) {
    alpha_mean <- rep(0, K)
    alpha_mean_source <- "zero"
  } else if (is.character(alpha_prior_mean) && length(alpha_prior_mean) == 1L) {
    alpha_mean_source <- alpha_prior_mean
    if (identical(alpha_prior_mean, "empirical_quantile")) {
      alpha_mean <- as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8))
    } else if (identical(alpha_prior_mean, "zero")) {
      alpha_mean <- rep(0, K)
    } else {
      stop("alpha_prior_mean must be numeric, NULL, 'zero', or 'empirical_quantile'.", call. = FALSE)
    }
  } else {
    alpha_mean <- as.numeric(alpha_prior_mean)
    alpha_mean_source <- "numeric"
    if (length(alpha_mean) == 1L) alpha_mean <- rep(alpha_mean, K)
  }
  if (length(alpha_mean) != K || any(!is.finite(alpha_mean))) {
    stop("alpha_prior_mean must be finite and have length 1 or length(tau).", call. = FALSE)
  }
  if (is.unsorted(alpha_mean, strictly = FALSE)) {
    alpha_mean <- sort(alpha_mean)
    alpha_mean_source <- paste0(alpha_mean_source, "_sorted")
  }
  alpha_sd <- as.numeric(alpha_prior_sd)
  if (length(alpha_sd) == 1L) alpha_sd <- rep(alpha_sd, K)
  if (length(alpha_sd) != K || any(is.na(alpha_sd)) || any(alpha_sd <= 0)) {
    stop("alpha_prior_sd must be positive and have length 1 or length(tau).", call. = FALSE)
  }
  if (any(!is.finite(alpha_sd) & !is.infinite(alpha_sd))) {
    stop("alpha_prior_sd must be positive finite values or Inf.", call. = FALSE)
  }
  alpha_precision <- ifelse(is.finite(alpha_sd), 1 / alpha_sd^2, 0)
  list(
    mean = alpha_mean,
    sd = alpha_sd,
    precision = alpha_precision,
    mean_source = alpha_mean_source,
    is_proper = any(alpha_precision > 0)
  )
}

app_joint_qvp_fit_al_mcmc_tiny <- function(
  y,
  Z,
  tau,
  n_iter = 200L,
  burn = 100L,
  thin = 1L,
  seed = NULL,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 0.1,
  b_sigma = 0.1,
  alpha_prior_mean = NULL,
  alpha_prior_sd = Inf,
  alpha_min_spacing = 0,
  max_dense_dim = 250L,
  sigma_bounds = c(1.0e-8, 1.0e8),
  init = NULL
) {
  if (!is.null(seed)) set.seed(seed)
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  n_iter <- as.integer(n_iter)
  burn <- as.integer(burn)
  thin <- as.integer(thin)
  if (n_iter <= 0L || burn < 0L || burn >= n_iter || thin <= 0L) {
    stop("Invalid MCMC iteration, burn, or thin controls.", call. = FALSE)
  }
  if (!is.finite(kappa) || kappa <= 0) stop("kappa must be positive.", call. = FALSE)
  a_sigma <- as.numeric(a_sigma)[[1L]]
  b_sigma <- as.numeric(b_sigma)[[1L]]
  if (!is.finite(a_sigma) || a_sigma <= 0 || !is.finite(b_sigma) || b_sigma <= 0) {
    stop("a_sigma and b_sigma must be positive.", call. = FALSE)
  }
  sigma_bounds <- as.numeric(sigma_bounds)
  if (length(sigma_bounds) != 2L || any(!is.finite(sigma_bounds)) ||
      sigma_bounds[[1L]] <= 0 || sigma_bounds[[2L]] <= sigma_bounds[[1L]]) {
    stop("sigma_bounds must be two increasing positive finite values.", call. = FALSE)
  }
  constants <- app_joint_qvp_al_constants(tau)
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, alpha_prior_mean, alpha_prior_sd)
  init <- app_joint_qvp_normalize_init(init, K, p)
  beta <- init$beta %||% rep(0, K * p)
  alpha <- init$alpha %||% sort(as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8)))
  sigma <- init$sigma %||% rep(max(stats::mad(y), 1.0e-3), K)
  v <- matrix(rep(sigma, each = Tn), nrow = Tn, ncol = K)
  rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = tau0, zeta2 = zeta2)
  keep_idx <- seq.int(burn + 1L, n_iter, by = thin)
  n_keep <- length(keep_idx)
  beta_draws <- matrix(NA_real_, nrow = n_keep, ncol = K * p)
  alpha_draws <- matrix(NA_real_, nrow = n_keep, ncol = K)
  sigma_draws <- matrix(NA_real_, nrow = n_keep, ncol = K)
  keep_pos <- 0L
  for (iter in seq_len(n_iter)) {
    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
    work <- app_joint_qvp_build_working_response(
      y = y,
      Z = Z,
      beta = beta,
      alpha = alpha,
      tau = tau,
      sigma = sigma,
      v = v,
      kappa = kappa,
      likelihood = "al"
    )
    beta_update <- app_joint_qvp_beta_gaussian_update(work$Z_stack, work$y_star, work$weights, prior$P_beta)
    beta <- app_joint_qvp_precision_draw(beta_update$mean, beta_update$precision, max_dense_dim = max_dense_dim)
    rhs_state <- app_joint_qvp_update_rhs_state(rhs_state, beta, K, p)
    beta_mat <- app_joint_qvp_beta_matrix(beta, K, p)
    fitted_no_alpha <- Z %*% beta_mat
    for (k in seq_len(K)) {
      wk <- kappa / (constants$B[[k]] * sigma[[k]] * v[, k])
      resid_alpha <- y - fitted_no_alpha[, k] - constants$A[[k]] * v[, k]
      prior_prec <- alpha_prior$precision[[k]]
      prec <- sum(wk) + prior_prec
      mean <- (sum(wk * resid_alpha) + prior_prec * alpha_prior$mean[[k]]) / prec
      lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + alpha_min_spacing
      upper <- if (k == K) Inf else alpha[[k + 1L]] - alpha_min_spacing
      if (lower >= upper) stop("Ordered intercept bounds collapsed.", call. = FALSE)
      alpha[[k]] <- app_joint_qvp_rtruncnorm(1, mean = mean, sd = sqrt(1 / prec), lower = lower, upper = upper)
    }
    fitted_no_alpha <- Z %*% beta_mat
    for (k in seq_len(K)) {
      resid <- y - alpha[[k]] - fitted_no_alpha[, k]
      chi <- kappa * resid^2 / (constants$B[[k]] * sigma[[k]])
      psi <- kappa * (constants$A[[k]]^2 / (constants$B[[k]] * sigma[[k]]) + 2 / sigma[[k]])
      v[, k] <- app_joint_qvp_rgig(lambda = 1 - kappa / 2, chi = chi, psi = psi, current = v[, k])
      sigma_rate <- kappa * (
        sum(v[, k]) +
          0.5 * sum((resid - constants$A[[k]] * v[, k])^2 / (constants$B[[k]] * v[, k]))
      )
      sigma[[k]] <- app_joint_qvp_rinvgamma(1, shape = a_sigma + 1.5 * kappa * Tn, rate = b_sigma + sigma_rate)
      sigma[[k]] <- min(max(sigma[[k]], sigma_bounds[[1L]]), sigma_bounds[[2L]])
    }
    if (iter %in% keep_idx) {
      keep_pos <- keep_pos + 1L
      beta_draws[keep_pos, ] <- beta
      alpha_draws[keep_pos, ] <- alpha
      sigma_draws[keep_pos, ] <- sigma
    }
  }
  beta_mean <- colMeans(beta_draws)
  alpha_mean <- colMeans(alpha_draws)
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) +
    matrix(alpha_mean, nrow = Tn, ncol = K, byrow = TRUE)
  out <- list(
    beta_draws = beta_draws,
    alpha_draws = alpha_draws,
    sigma_draws = sigma_draws,
    beta_mean = beta_mean,
    alpha_mean = alpha_mean,
    sigma_mean = colMeans(sigma_draws),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    tau = tau,
    kappa = kappa,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior$mean,
    alpha_prior_sd = alpha_prior$sd,
    alpha_prior_mean_source = alpha_prior$mean_source,
    seed = seed,
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("joint_qvp_al_mcmc_tiny_%s", format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau,
      kappa = kappa,
      likelihood = "al",
      inference = "mcmc_tiny",
      seed = seed,
      status = "prototype_success"
    )
  )
  out$init_source <- if (is.null(init)) "default" else "provided"
  class(out) <- c("joint_qvp_qdesn_tiny_fit", "list")
  out
}

app_joint_qvp_write_csv <- function(x, path) {
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

app_joint_qvp_parse_tau_spec <- function(x, default = c(0.25, 0.75)) {
  if (is.null(x) || length(x) == 0L || is.na(x[[1L]]) || !nzchar(as.character(x[[1L]]))) {
    return(app_joint_qvp_validate_tau_grid(default))
  }
  if (is.numeric(x)) return(app_joint_qvp_validate_tau_grid(x))
  vals <- strsplit(as.character(x[[1L]]), ",", fixed = TRUE)[[1L]]
  app_joint_qvp_validate_tau_grid(as.numeric(trimws(vals)))
}

app_joint_qvp_l2_distance <- function(x, y) {
  x <- as.numeric(x)
  y <- as.numeric(y)
  if (length(x) != length(y)) return(NA_real_)
  sqrt(sum((x - y)^2))
}

app_joint_qvp_default_validation_thresholds <- function() {
  data.frame(
    criterion = c(
      "artifact_reproducibility",
      "finite_vb_summaries",
      "finite_al_partial_elbo_terms",
      "al_objective_monotonicity_review",
      "finite_rhs_prior_summary",
      "warmstarted_mcmc_finite",
      "fitted_crossing_pairs",
      "vb_mcmc_normalized_distance_pass",
      "vb_mcmc_normalized_distance_review",
      "vb_nonconvergence"
    ),
    gate = c(
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "review",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "pass_threshold",
      "review",
      "review"
    ),
    threshold = c(
      "identical_sha256_for_repeated_same_config",
      "all_finite",
      "included_terms_all_finite_missing_terms_statused",
      "max_drop <= 1e-8_pass_else_review",
      "all_finite_and_positive",
      "all_finite_draws",
      "0",
      "5",
      ">5",
      "status_recorded_not_promoted"
    ),
    rationale = c(
      "Repo validation artifacts are hash-pinned before use.",
      "Validation cannot proceed with non-finite summaries.",
      "AL-VB partial-ELBO accounting must be auditable before full ELBO promotion.",
      "Current AL-VB objective is RHS-accounted but has approximate log-precision and point-alpha treatment, so monotonicity failures are review gates.",
      "RHS shrinkage updates must remain numerically valid.",
      "MCMC is the slower reference layer initialized from VB.",
      "Joint quantile artifacts should not silently promote crossed fitted summaries.",
      "Loose normalized-distance pass threshold for tiny short-chain MCMC smoke references.",
      "Tiny short-chain MCMC distance is recorded for review, not used as a hard fail before a stable long-chain reference is defined.",
      "Economical VB runs may hit max_iter, but must report that state and remain review-only."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_method_to_warmstart <- function(method) {
  out <- rep(NA_character_, length(method))
  out[method == "al_vb"] <- "al_mcmc_from_vb"
  out[method == "exal_vb_ld"] <- "exal_mcmc_from_vb_ld"
  out
}

app_joint_qvp_assess_synthetic_validation <- function(
  fit_summary,
  warmstart_summary,
  pass_distance = 5,
  fail_distance = 10
) {
  if (!nrow(fit_summary)) return(data.frame())
  rows <- vector("list", nrow(fit_summary))
  for (ii in seq_len(nrow(fit_summary))) {
    fit <- fit_summary[ii, , drop = FALSE]
    warm_method <- app_joint_qvp_method_to_warmstart(fit$method)
    if ("case_id" %in% names(fit_summary) && "case_id" %in% names(warmstart_summary)) {
      warm <- warmstart_summary[
        warmstart_summary$case_id == fit$case_id[[1L]] &
          warmstart_summary$method == warm_method,
        ,
        drop = FALSE
      ]
    } else {
      warm <- warmstart_summary[
        warmstart_summary$scenario == fit$scenario[[1L]] &
          warmstart_summary$method == warm_method,
        ,
        drop = FALSE
      ]
    }
    beta_norm <- fit$beta_l2_to_mcmc / (sqrt(fit$p * fit$K) * (1 + fit$beta_l2))
    alpha_norm <- fit$alpha_l2_to_mcmc / (sqrt(fit$K) * (1 + fit$sigma_mean))
    sigma_norm <- fit$sigma_l2_to_mcmc / (sqrt(fit$K) * (1 + fit$sigma_mean))
    gamma_norm <- if (is.finite(fit$gamma_l2_to_mcmc)) {
      fit$gamma_l2_to_mcmc / (sqrt(fit$K) * (1 + abs(fit$gamma_mean)))
    } else {
      NA_real_
    }
    max_norm <- max(c(beta_norm, alpha_norm, sigma_norm, gamma_norm), na.rm = TRUE)
	    finite_required <- all(is.finite(c(
	      fit$beta_l2,
	      fit$sigma_mean,
	      fit$rhs_mean_precision,
      fit$rhs_max_precision,
      fit$final_monitor,
      fit$beta_l2_to_mcmc,
	      fit$alpha_l2_to_mcmc,
	      fit$sigma_l2_to_mcmc
	    )))
	    partial_elbo_ok <- !"final_partial_elbo" %in% names(fit) ||
	      !identical(as.character(fit$method[[1L]]), "al_vb") ||
	      is.finite(fit$final_partial_elbo[[1L]])
	    objective_status <- if ("objective_status" %in% names(fit)) {
	      as.character(fit$objective_status[[1L]])
	    } else {
	      "not_available"
	    }
	    objective_ok <- !identical(as.character(fit$method[[1L]]), "al_vb") ||
	      objective_status %in% c("pass", "review")
	    warm_ok <- nrow(warm) == 1L &&
	      identical(as.character(warm$init_source[[1L]]), "provided") &&
	      isTRUE(as.logical(warm$all_finite[[1L]]))
	    hard_fail <- !finite_required ||
	      !partial_elbo_ok ||
	      !objective_ok ||
	      !is.finite(fit$rhs_mean_precision) ||
	      fit$rhs_mean_precision <= 0 ||
	      fit$total_crossing_pairs > 0 ||
      !warm_ok ||
      !is.finite(max_norm)
    distance_status <- if (!is.finite(max_norm) || max_norm > fail_distance) {
      "review"
    } else if (max_norm > pass_distance) {
      "review"
    } else {
      "pass"
    }
	    gate_status <- if (hard_fail) {
	      "fail"
	    } else if (!isTRUE(fit$converged) || identical(distance_status, "review") ||
	        (identical(as.character(fit$method[[1L]]), "al_vb") && !identical(objective_status, "pass"))) {
	      "review"
	    } else {
	      "pass"
    }
    rows[[ii]] <- data.frame(
      case_id = fit$case_id %||% NA_character_,
      scenario = fit$scenario,
      method = fit$method,
      likelihood = fit$likelihood,
      inference = fit$inference,
      implementation_status = if (hard_fail) "fail" else "pass",
	      distance_status = distance_status,
	      objective_status = objective_status,
	      convergence_status = if (isTRUE(fit$converged)) "pass" else "review",
	      gate_status = gate_status,
      beta_normalized_distance = beta_norm,
      alpha_normalized_distance = alpha_norm,
      sigma_normalized_distance = sigma_norm,
      gamma_normalized_distance = gamma_norm,
      max_normalized_distance = max_norm,
      crossing_pairs = fit$total_crossing_pairs,
	      warmstart_ok = warm_ok,
	      notes = if (hard_fail) {
	        "hard validation criterion failed"
	      } else if (identical(as.character(fit$method[[1L]]), "al_vb") && !identical(objective_status, "pass")) {
	        "AL-VB objective monotonicity requires review"
	      } else if (!isTRUE(fit$converged)) {
	        "prototype reached max_iter; keep as review-only"
      } else if (identical(distance_status, "review")) {
        "VB/MCMC distance requires threshold review"
      } else {
        "implementation gate passed"
      },
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_run_synthetic_vb_validation <- function(
  out_dir,
  scenarios = NULL,
  kappa = 1,
  al_max_iter = 40L,
  exal_max_iter = 20L,
  mcmc_n_iter = 10L,
  mcmc_burn = 5L,
  mcmc_thin = 2L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% data.frame(
    scenario = c("parallel", "parallel", "slope_variation", "crossing_pressure"),
    seed = c(20260709L, 20260710L, 20260711L, 20260712L),
    Tn = c(16L, 18L, 18L, 18L),
    p = c(2L, 2L, 2L, 2L),
    tau = c("0.5", "0.25,0.75", "0.25,0.75", "0.25,0.5,0.75"),
    noise_sd = c(0.05, 0.05, 0.05, 0.05),
    stringsAsFactors = FALSE
  )
  fit_rows <- list()
  crossing_rows <- list()
	  rhs_rows <- list()
	  monitor_rows <- list()
	  elbo_rows <- list()
	  objective_rows <- list()
	  warmstart_rows <- list()
  config_rows <- list()
  threshold_spec <- app_joint_qvp_default_validation_thresholds()
  row_id <- 0L
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, ]
    tau <- app_joint_qvp_parse_tau_spec(sc$tau %||% NA_character_)
    case_id <- sprintf("%s_seed%s_K%s", sc$scenario, sc$seed, length(tau))
    fixture <- app_joint_qvp_simulate_synthetic(
      Tn = sc$Tn,
      p = sc$p,
      tau = tau,
      scenario = sc$scenario,
      seed = sc$seed,
      noise_sd = sc$noise_sd
    )
    al_fit <- app_joint_qvp_fit_al_vb_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = al_max_iter,
      tol = 1.0e-4,
      kappa = kappa,
      tau0 = 1
    )
    exal_fit <- app_joint_qvp_fit_exal_vb_ld_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = exal_max_iter,
      tol = 1.0e-4,
      kappa = kappa,
      tau0 = 1,
      init = al_fit
    )
    al_mcmc <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_n_iter,
      burn = mcmc_burn,
      thin = mcmc_thin,
      seed = sc$seed + 100L,
      kappa = kappa,
      init = al_fit,
      max_dense_dim = 20L
    )
    exal_mcmc <- app_joint_qvp_fit_exal_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_n_iter,
      burn = mcmc_burn,
      thin = mcmc_thin,
      seed = sc$seed + 200L,
      kappa = kappa,
      init = exal_fit,
      max_dense_dim = 20L
    )
    fits <- list(al_vb = al_fit, exal_vb_ld = exal_fit)
    mcmc_refs <- list(al_vb = al_mcmc, exal_vb_ld = exal_mcmc)
	    for (method in names(fits)) {
	      fit <- fits[[method]]
	      mcmc_ref <- mcmc_refs[[method]]
	      row_id <- row_id + 1L
	      crossing <- fit$crossing_diagnostics
	      objective <- fit$objective_diagnostics %||% app_joint_qvp_objective_diagnostics(
	        trace = fit$trace,
	        value_col = "monitor",
	        objective_label = fit$monitor_label %||% "coordinate_monitor",
	        tolerance = 1.0e-8,
	        approximation_status = if (identical(method, "exal_vb_ld")) {
	          "approximate_vb_ld_monitor"
	        } else {
	          "coordinate_monitor"
	        }
	      )
	      fit_rows[[row_id]] <- data.frame(
        case_id = case_id,
        scenario = sc$scenario,
        seed = sc$seed,
        method = method,
        likelihood = fit$manifest$likelihood[[1L]],
        inference = fit$manifest$inference[[1L]],
        status = fit$manifest$status[[1L]],
        converged = isTRUE(fit$converged),
        Tn = sc$Tn,
        p = sc$p,
        K = length(fixture$tau),
        kappa = kappa,
        beta_l2 = sqrt(sum(fit$beta_mean^2)),
        sigma_mean = mean(fit$sigma_mean),
	        gamma_mean = mean(fit$gamma_mean %||% NA_real_, na.rm = TRUE),
	        total_crossing_pairs = sum(crossing$n_crossing_pairs),
	        max_crossing_magnitude = max(crossing$max_crossing_magnitude),
	        rhs_mean_precision = mean(fit$rhs_prior_summary$mean_precision),
	        rhs_max_precision = max(fit$rhs_prior_summary$max_precision),
	        final_monitor = tail(fit$trace$monitor, 1L),
	        final_partial_elbo = if ("partial_elbo" %in% names(fit$trace)) {
	          tail(fit$trace$partial_elbo, 1L)
	        } else {
	          NA_real_
	        },
	        objective_status = objective$objective_status[[1L]],
	        objective_max_drop = objective$max_drop[[1L]],
	        objective_n_decreases = objective$n_decreases[[1L]],
	        beta_l2_to_mcmc = app_joint_qvp_l2_distance(fit$beta_mean, mcmc_ref$beta_mean),
	        alpha_l2_to_mcmc = app_joint_qvp_l2_distance(fit$alpha_mean, mcmc_ref$alpha_mean),
	        sigma_l2_to_mcmc = app_joint_qvp_l2_distance(fit$sigma_mean, mcmc_ref$sigma_mean),
	        gamma_l2_to_mcmc = app_joint_qvp_l2_distance(fit$gamma_mean %||% NA_real_, mcmc_ref$gamma_mean %||% NA_real_),
	        stringsAsFactors = FALSE
	      )
      crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
        case_id = case_id,
        scenario = sc$scenario,
        method = method,
        crossing,
        stringsAsFactors = FALSE
      )
      rhs_rows[[length(rhs_rows) + 1L]] <- cbind(
        case_id = case_id,
        scenario = sc$scenario,
        method = method,
        fit$rhs_prior_summary,
        stringsAsFactors = FALSE
      )
      monitor_rows[[length(monitor_rows) + 1L]] <- cbind(
	        case_id = case_id,
	        scenario = sc$scenario,
	        method = method,
	        fit$monitor_terms,
	        stringsAsFactors = FALSE
	      )
	      if (!is.null(fit$elbo_terms)) {
	        elbo_rows[[length(elbo_rows) + 1L]] <- cbind(
	          case_id = case_id,
	          scenario = sc$scenario,
	          method = method,
	          fit$elbo_terms,
	          stringsAsFactors = FALSE
	        )
	      }
	      objective_rows[[length(objective_rows) + 1L]] <- cbind(
	        case_id = case_id,
	        scenario = sc$scenario,
	        method = method,
	        objective,
	        stringsAsFactors = FALSE
	      )
	    }
    warmstart_rows[[length(warmstart_rows) + 1L]] <- data.frame(
      case_id = case_id,
      scenario = sc$scenario,
      method = c("al_mcmc_from_vb", "exal_mcmc_from_vb_ld"),
      seed = c(sc$seed + 100L, sc$seed + 200L),
      init_source = c(al_mcmc$init_source, exal_mcmc$init_source),
      n_beta_draw_rows = c(nrow(al_mcmc$beta_draws), nrow(exal_mcmc$beta_draws)),
      all_finite = c(all(is.finite(al_mcmc$beta_draws)), all(is.finite(exal_mcmc$beta_draws))),
      stringsAsFactors = FALSE
    )
    config_rows[[length(config_rows) + 1L]] <- data.frame(
      case_id = case_id,
      scenario = sc$scenario,
      seed = sc$seed,
      Tn = sc$Tn,
      p = sc$p,
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = sc$noise_sd,
      kappa = kappa,
      al_max_iter = al_max_iter,
      exal_max_iter = exal_max_iter,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      stringsAsFactors = FALSE
    )
  }
  fit_summary <- do.call(rbind, fit_rows)
  warmstart_summary <- do.call(rbind, warmstart_rows)
  validation_assessment <- app_joint_qvp_assess_synthetic_validation(
    fit_summary = fit_summary,
    warmstart_summary = warmstart_summary
  )
	  paths <- c(
	    run_config = app_joint_qvp_write_csv(do.call(rbind, config_rows), file.path(out_dir, "run_config.csv")),
	    validation_thresholds = app_joint_qvp_write_csv(threshold_spec, file.path(out_dir, "validation_thresholds.csv")),
	    validation_assessment = app_joint_qvp_write_csv(validation_assessment, file.path(out_dir, "validation_assessment.csv")),
	    fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
	    crossing_summary = app_joint_qvp_write_csv(do.call(rbind, crossing_rows), file.path(out_dir, "crossing_summary.csv")),
	    rhs_prior_summary = app_joint_qvp_write_csv(do.call(rbind, rhs_rows), file.path(out_dir, "rhs_prior_summary.csv")),
	    monitor_terms = app_joint_qvp_write_csv(do.call(rbind, monitor_rows), file.path(out_dir, "monitor_terms.csv")),
	    elbo_terms = app_joint_qvp_write_csv(do.call(rbind, elbo_rows), file.path(out_dir, "elbo_terms.csv")),
	    objective_diagnostics = app_joint_qvp_write_csv(do.call(rbind, objective_rows), file.path(out_dir, "objective_diagnostics.csv")),
	    warmstart_summary = app_joint_qvp_write_csv(warmstart_summary, file.path(out_dir, "warmstart_summary.csv"))
	  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_default_objective_stress_scenarios <- function() {
  data.frame(
    stress_case = c(
      "k1_baseline",
      "wide_tau_parallel",
      "slope_high_noise",
      "crossing_pressure",
      "strong_shrinkage",
      "weak_shrinkage"
    ),
    scenario = c(
      "parallel",
      "parallel",
      "slope_variation",
      "crossing_pressure",
      "slope_variation",
      "slope_variation"
    ),
    seed = c(20260721L, 20260722L, 20260723L, 20260724L, 20260725L, 20260726L),
    Tn = c(14L, 24L, 20L, 20L, 18L, 18L),
    p = c(2L, 3L, 3L, 2L, 2L, 2L),
    tau = c("0.5", "0.1,0.5,0.9", "0.2,0.8", "0.2,0.5,0.8", "0.25,0.75", "0.25,0.75"),
    noise_sd = c(0.05, 0.05, 0.2, 0.05, 0.05, 0.05),
    kappa = c(0.5, 0.5, 0.5, 0.5, 0.75, 0.75),
    tau0 = c(1, 1, 1, 1, 0.25, 3),
    max_iter = c(220L, 220L, 180L, 100L, 60L, 60L),
    rhs_vb_inner = c(5L, 5L, 5L, 5L, 7L, 7L),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_default_objective_stress_thresholds <- function() {
  data.frame(
    criterion = c(
      "artifact_reproducibility",
      "finite_al_vb_summaries",
      "finite_objective_terms",
      "al_objective_monotonicity",
      "finite_rhs_prior_summary",
      "fitted_crossing_pairs",
      "vb_nonconvergence"
    ),
    gate = c(
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "pass_threshold",
      "hard_fail",
      "hard_fail",
      "review"
    ),
    threshold = c(
      "identical_sha256_for_repeated_same_config",
      "all_finite",
      "included_terms_all_finite_missing_terms_statused",
      "max_drop <= 1e-8",
      "all_finite_and_positive",
      "0",
      "status_recorded_not_promoted"
    ),
    rationale = c(
      "Stress artifacts are hash-pinned before they inform validation choices.",
      "AL-VB stress summaries must remain numerically valid.",
      "Objective accounting terms must be auditable in every stress case.",
      "Current accounted AL-VB objective should not decrease on stress fixtures before promotion.",
      "RHS shrinkage precisions must remain finite and positive under stress.",
      "Stress fixtures should not silently promote crossed fitted summaries.",
      "Max-iteration status is review-only until larger-run controls are calibrated."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_assess_objective_stress <- function(fit_summary) {
  if (!nrow(fit_summary)) return(data.frame())
  rows <- vector("list", nrow(fit_summary))
  for (ii in seq_len(nrow(fit_summary))) {
    fit <- fit_summary[ii, , drop = FALSE]
    finite_required <- all(is.finite(c(
      fit$beta_l2,
      fit$sigma_mean,
      fit$rhs_mean_precision,
      fit$rhs_max_precision,
      fit$final_partial_elbo,
      fit$objective_max_drop
    )))
    hard_fail <- !finite_required ||
      !identical(as.character(fit$objective_status[[1L]]), "pass") ||
      !is.finite(fit$rhs_mean_precision) ||
      fit$rhs_mean_precision <= 0 ||
      fit$total_crossing_pairs > 0
    gate_status <- if (hard_fail) {
      "fail"
    } else if (!isTRUE(fit$converged)) {
      "review"
    } else {
      "pass"
    }
    rows[[ii]] <- data.frame(
      case_id = fit$case_id,
      stress_case = fit$stress_case,
      scenario = fit$scenario,
      implementation_status = if (hard_fail) "fail" else "pass",
      objective_status = fit$objective_status,
      convergence_status = if (isTRUE(fit$converged)) "pass" else "review",
      gate_status = gate_status,
      objective_max_drop = fit$objective_max_drop,
      objective_n_decreases = fit$objective_n_decreases,
      crossing_pairs = fit$total_crossing_pairs,
      notes = if (hard_fail) {
        "hard stress criterion failed"
      } else if (!isTRUE(fit$converged)) {
        "stress run reached max_iter; keep as review-only"
      } else {
        "stress gate passed"
      },
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_run_al_vb_objective_stress <- function(
  out_dir,
  scenarios = NULL,
  default_max_iter = 60L,
  default_kappa = 0.5,
  default_tau0 = 1,
  default_rhs_vb_inner = 5L
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_objective_stress_scenarios()
  get_cell <- function(sc, name, default) {
    if (!name %in% names(sc) || is.na(sc[[name]][[1L]])) return(default)
    sc[[name]][[1L]]
  }
  fit_rows <- list()
  crossing_rows <- list()
  rhs_rows <- list()
  objective_rows <- list()
  elbo_rows <- list()
  config_rows <- list()
  threshold_spec <- app_joint_qvp_default_objective_stress_thresholds()
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, , drop = FALSE]
    tau <- app_joint_qvp_parse_tau_spec(get_cell(sc, "tau", "0.25,0.75"))
    stress_case <- as.character(get_cell(sc, "stress_case", as.character(get_cell(sc, "scenario", "stress"))))
    scenario <- as.character(get_cell(sc, "scenario", "parallel"))
    seed <- as.integer(get_cell(sc, "seed", 20260701L + ii))
    Tn <- as.integer(get_cell(sc, "Tn", 18L))
    p <- as.integer(get_cell(sc, "p", 2L))
    noise_sd <- as.numeric(get_cell(sc, "noise_sd", 0.05))
    kappa <- as.numeric(get_cell(sc, "kappa", default_kappa))
    tau0 <- as.numeric(get_cell(sc, "tau0", default_tau0))
    max_iter <- as.integer(get_cell(sc, "max_iter", default_max_iter))
    rhs_vb_inner <- as.integer(get_cell(sc, "rhs_vb_inner", default_rhs_vb_inner))
    case_id <- sprintf("%s_seed%s_K%s", stress_case, seed, length(tau))
    fixture <- app_joint_qvp_simulate_synthetic(
      Tn = Tn,
      p = p,
      tau = tau,
      scenario = scenario,
      seed = seed,
      noise_sd = noise_sd
    )
    fit <- app_joint_qvp_fit_al_vb_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = max_iter,
      tol = 1.0e-4,
      kappa = kappa,
      tau0 = tau0,
      rhs_vb_inner = rhs_vb_inner
    )
    crossing <- fit$crossing_diagnostics
    objective <- fit$objective_diagnostics
    fit_rows[[length(fit_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      seed = seed,
      status = fit$manifest$status[[1L]],
      converged = isTRUE(fit$converged),
      Tn = Tn,
      p = p,
      K = length(fixture$tau),
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = noise_sd,
      kappa = kappa,
      tau0 = tau0,
      max_iter = max_iter,
      rhs_vb_inner = rhs_vb_inner,
      beta_l2 = sqrt(sum(fit$beta_mean^2)),
      sigma_mean = mean(fit$sigma_mean),
      rhs_mean_precision = mean(fit$rhs_prior_summary$mean_precision),
      rhs_max_precision = max(fit$rhs_prior_summary$max_precision),
      final_partial_elbo = tail(fit$trace$partial_elbo, 1L),
      objective_status = objective$objective_status[[1L]],
      objective_max_drop = objective$max_drop[[1L]],
      objective_n_decreases = objective$n_decreases[[1L]],
      total_crossing_pairs = sum(crossing$n_crossing_pairs),
      max_crossing_magnitude = max(crossing$max_crossing_magnitude),
      stringsAsFactors = FALSE
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      crossing,
      stringsAsFactors = FALSE
    )
    rhs_rows[[length(rhs_rows) + 1L]] <- cbind(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      fit$rhs_prior_summary,
      stringsAsFactors = FALSE
    )
    objective_rows[[length(objective_rows) + 1L]] <- cbind(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      objective,
      stringsAsFactors = FALSE
    )
    final_elbo_terms <- fit$elbo_terms[
      fit$elbo_terms$iter == max(fit$elbo_terms$iter),
      ,
      drop = FALSE
    ]
    elbo_rows[[length(elbo_rows) + 1L]] <- cbind(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      final_elbo_terms,
      stringsAsFactors = FALSE
    )
    config_rows[[length(config_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      seed = seed,
      Tn = Tn,
      p = p,
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = noise_sd,
      kappa = kappa,
      tau0 = tau0,
      max_iter = max_iter,
      rhs_vb_inner = rhs_vb_inner,
      stringsAsFactors = FALSE
    )
  }
  fit_summary <- do.call(rbind, fit_rows)
  stress_assessment <- app_joint_qvp_assess_objective_stress(fit_summary)
  paths <- c(
    run_config = app_joint_qvp_write_csv(do.call(rbind, config_rows), file.path(out_dir, "run_config.csv")),
    stress_thresholds = app_joint_qvp_write_csv(threshold_spec, file.path(out_dir, "stress_thresholds.csv")),
    stress_assessment = app_joint_qvp_write_csv(stress_assessment, file.path(out_dir, "stress_assessment.csv")),
    fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(do.call(rbind, objective_rows), file.path(out_dir, "objective_diagnostics.csv")),
    crossing_summary = app_joint_qvp_write_csv(do.call(rbind, crossing_rows), file.path(out_dir, "crossing_summary.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(do.call(rbind, rhs_rows), file.path(out_dir, "rhs_prior_summary.csv")),
    elbo_terms = app_joint_qvp_write_csv(do.call(rbind, elbo_rows), file.path(out_dir, "elbo_terms.csv"))
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_default_mcmc_calibration_thresholds <- function() {
  data.frame(
    criterion = c(
      "artifact_reproducibility",
      "vb_converged",
      "warmstarted_mcmc",
      "finite_mcmc_draws",
      "finite_vb_mcmc_distances",
      "fitted_crossing_pairs",
      "finite_mean_sigma_prior",
      "bounded_sigma_reference",
      "sigma_bound_hit_fraction",
      "vb_mcmc_normalized_distance_pass",
      "vb_mcmc_normalized_distance_review"
    ),
    gate = c(
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "documented_reference_control",
      "documented_reference_control",
      "review",
      "pass_threshold",
      "review"
    ),
    threshold = c(
      "identical_sha256_for_repeated_same_config",
      "vb_status_is_prototype_success",
      "init_source_is_provided",
      "all_draw_blocks_finite",
      "all_distance_summaries_finite",
      "0",
      "a_sigma = 2, b_sigma = 1",
      "sigma_upper = max(1, 50 * max(vb_sigma_mean))",
      "upper_bound_hit_fraction == 0 for pass",
      "max_normalized_distance <= 5",
      "max_normalized_distance > 5"
    ),
    rationale = c(
      "Calibration artifacts must be reproducible before informing thresholds.",
      "Longer MCMC calibration should start from a converged VB state.",
      "The MCMC reference layer must use the VB state as initialization.",
      "MCMC references cannot calibrate thresholds with non-finite draws.",
      "VB/MCMC agreement metrics must be numerically valid.",
      "Calibration should not silently promote crossed fitted summaries.",
      "The calibration reference uses a finite-mean scale prior instead of the weak infinite-mean prototype prior.",
      "The tiny AL-MCMC scale block is bounded broadly relative to the converged VB scale to prevent numerical-reference explosions from driving threshold calibration.",
      "A positive bound-hit fraction indicates bound-sensitive MCMC reference behavior and remains review-only.",
      "Initial loose pass rule inherited from the synthetic smoke policy.",
      "Distances above the loose rule are retained for review and threshold calibration."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_mcmc_draw_summary <- function(fit, case_id, stress_case, scenario, sigma_bounds = c(NA_real_, NA_real_)) {
  blocks <- list(
    beta = fit$beta_draws,
    alpha = fit$alpha_draws,
    sigma = fit$sigma_draws
  )
  rows <- lapply(names(blocks), function(block) {
    x <- blocks[[block]]
    finite <- all(is.finite(x))
    lower_bound <- if (identical(block, "sigma")) sigma_bounds[[1L]] else NA_real_
    upper_bound <- if (identical(block, "sigma")) sigma_bounds[[2L]] else NA_real_
    lower_hit_fraction <- if (identical(block, "sigma") && is.finite(lower_bound)) {
      mean(x <= lower_bound * (1 + 1.0e-8))
    } else {
      NA_real_
    }
    upper_hit_fraction <- if (identical(block, "sigma") && is.finite(upper_bound)) {
      mean(x >= upper_bound * (1 - 1.0e-8))
    } else {
      NA_real_
    }
    data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      block = block,
      n_draws = nrow(x),
      n_parameters = ncol(x),
      all_finite = finite,
      mean_abs_draw_mean = mean(abs(colMeans(x))),
      mean_draw_sd = mean(apply(x, 2L, stats::sd)),
      min_value = min(x),
      max_value = max(x),
      lower_bound = lower_bound,
      upper_bound = upper_bound,
      lower_bound_hit_fraction = lower_hit_fraction,
      upper_bound_hit_fraction = upper_hit_fraction,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_vb_mcmc_distance_summary <- function(vb_fit, mcmc_fit, case_id, stress_case, scenario, Tn, p, K) {
  beta_l2 <- app_joint_qvp_l2_distance(vb_fit$beta_mean, mcmc_fit$beta_mean)
  alpha_l2 <- app_joint_qvp_l2_distance(vb_fit$alpha_mean, mcmc_fit$alpha_mean)
  sigma_l2 <- app_joint_qvp_l2_distance(vb_fit$sigma_mean, mcmc_fit$sigma_mean)
  qhat_l2 <- app_joint_qvp_l2_distance(vb_fit$qhat_mean, mcmc_fit$qhat_mean)
  beta_norm <- beta_l2 / (sqrt(p * K) * (1 + sqrt(sum(vb_fit$beta_mean^2))))
  alpha_norm <- alpha_l2 / (sqrt(K) * (1 + mean(vb_fit$sigma_mean)))
  sigma_norm <- sigma_l2 / (sqrt(K) * (1 + mean(vb_fit$sigma_mean)))
  qhat_norm <- qhat_l2 / (sqrt(Tn * K) * (1 + sqrt(mean(vb_fit$qhat_mean^2))))
  max_norm <- max(c(beta_norm, alpha_norm, sigma_norm, qhat_norm), na.rm = TRUE)
  data.frame(
    case_id = case_id,
    stress_case = stress_case,
    scenario = scenario,
    beta_l2_to_mcmc = beta_l2,
    alpha_l2_to_mcmc = alpha_l2,
    sigma_l2_to_mcmc = sigma_l2,
    qhat_l2_to_mcmc = qhat_l2,
    beta_normalized_distance = beta_norm,
    alpha_normalized_distance = alpha_norm,
    sigma_normalized_distance = sigma_norm,
    qhat_normalized_distance = qhat_norm,
    max_normalized_distance = max_norm,
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_assess_mcmc_calibration <- function(fit_summary, distance_pass = 5) {
  if (!nrow(fit_summary)) return(data.frame())
  rows <- vector("list", nrow(fit_summary))
  for (ii in seq_len(nrow(fit_summary))) {
    fit <- fit_summary[ii, , drop = FALSE]
    finite_required <- all(is.finite(c(
      fit$vb_beta_l2,
      fit$vb_sigma_mean,
      fit$mcmc_sigma_mean,
      fit$beta_normalized_distance,
      fit$alpha_normalized_distance,
      fit$sigma_normalized_distance,
      fit$qhat_normalized_distance,
      fit$max_normalized_distance,
      fit$max_sigma_upper_bound_hit_fraction
    )))
    hard_fail <- !finite_required ||
      !isTRUE(fit$vb_converged) ||
      !identical(as.character(fit$mcmc_init_source[[1L]]), "provided") ||
      !isTRUE(fit$mcmc_draws_all_finite) ||
      fit$total_vb_crossing_pairs > 0 ||
      fit$total_mcmc_crossing_pairs > 0
    reference_status <- if (is.finite(fit$max_sigma_upper_bound_hit_fraction) &&
        fit$max_sigma_upper_bound_hit_fraction <= 0) {
      "pass"
    } else {
      "review"
    }
    distance_status <- if (is.finite(fit$max_normalized_distance) &&
        fit$max_normalized_distance <= distance_pass) {
      "pass"
    } else {
      "review"
    }
    gate_status <- if (hard_fail) {
      "fail"
    } else if (identical(distance_status, "review") || identical(reference_status, "review")) {
      "review"
    } else {
      "pass"
    }
    rows[[ii]] <- data.frame(
      case_id = fit$case_id,
      stress_case = fit$stress_case,
      scenario = fit$scenario,
      implementation_status = if (hard_fail) "fail" else "pass",
      reference_status = reference_status,
      distance_status = distance_status,
      gate_status = gate_status,
      max_normalized_distance = fit$max_normalized_distance,
      max_sigma_upper_bound_hit_fraction = fit$max_sigma_upper_bound_hit_fraction,
      crossing_pairs = fit$total_vb_crossing_pairs + fit$total_mcmc_crossing_pairs,
      warmstart_ok = identical(as.character(fit$mcmc_init_source[[1L]]), "provided"),
      notes = if (hard_fail) {
        "hard calibration criterion failed"
      } else if (identical(reference_status, "review")) {
        "sigma bound hit fraction retained for reference review"
      } else if (identical(distance_status, "review")) {
        "VB/MCMC distance retained for threshold review"
      } else {
        "calibration gate passed"
      },
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_git_field <- function(args, root = app_repo_root()) {
  out <- tryCatch(
    system2("git", c("-C", root, args), stdout = TRUE, stderr = TRUE),
    error = function(e) NA_character_
  )
  if (!length(out)) return(NA_character_)
  paste(out, collapse = "\n")
}

app_joint_qvp_sha256_text <- function(x) {
  tmp <- tempfile("joint_qvp_text_hash_")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(enc2utf8(as.character(x)), tmp, useBytes = TRUE)
  app_sha256_file(tmp)
}

app_joint_qvp_provenance_rows <- function() {
  status <- app_joint_qvp_git_field(c("status", "--short"))
  data.frame(
    key = c(
      "repo_root",
      "git_branch",
      "git_head",
      "git_status_sha256",
      "r_version",
      "rng_kind"
    ),
    value = c(
      app_repo_root(),
      app_joint_qvp_git_field(c("rev-parse", "--abbrev-ref", "HEAD")),
      app_joint_qvp_git_field(c("rev-parse", "HEAD")),
      app_joint_qvp_sha256_text(status %||% ""),
      R.version.string,
      paste(RNGkind(), collapse = ",")
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_run_al_vb_mcmc_calibration <- function(
  out_dir,
  scenarios = NULL,
  default_mcmc_n_iter = 120L,
  default_mcmc_burn = 60L,
  default_mcmc_thin = 5L,
  mcmc_seed_offset = 1000L,
  default_a_sigma = 2,
  default_b_sigma = 1,
  sigma_lower_bound = 1.0e-8,
  sigma_upper_multiplier = 50,
  sigma_upper_floor = 1
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_objective_stress_scenarios()
  get_cell <- function(sc, name, default) {
    if (!name %in% names(sc) || is.na(sc[[name]][[1L]])) return(default)
    sc[[name]][[1L]]
  }
  fit_rows <- list()
  distance_rows <- list()
  draw_rows <- list()
  crossing_rows <- list()
  rhs_rows <- list()
  objective_rows <- list()
  elbo_rows <- list()
  config_rows <- list()
  threshold_spec <- app_joint_qvp_default_mcmc_calibration_thresholds()
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, , drop = FALSE]
    tau <- app_joint_qvp_parse_tau_spec(get_cell(sc, "tau", "0.25,0.75"))
    stress_case <- as.character(get_cell(sc, "stress_case", as.character(get_cell(sc, "scenario", "stress"))))
    scenario <- as.character(get_cell(sc, "scenario", "parallel"))
    seed <- as.integer(get_cell(sc, "seed", 20260701L + ii))
    Tn <- as.integer(get_cell(sc, "Tn", 18L))
    p <- as.integer(get_cell(sc, "p", 2L))
    noise_sd <- as.numeric(get_cell(sc, "noise_sd", 0.05))
    kappa <- as.numeric(get_cell(sc, "kappa", 0.5))
    tau0 <- as.numeric(get_cell(sc, "tau0", 1))
    a_sigma <- as.numeric(get_cell(sc, "a_sigma", default_a_sigma))
    b_sigma <- as.numeric(get_cell(sc, "b_sigma", default_b_sigma))
    max_iter <- as.integer(get_cell(sc, "max_iter", 100L))
    rhs_vb_inner <- as.integer(get_cell(sc, "rhs_vb_inner", 5L))
    mcmc_n_iter <- as.integer(get_cell(sc, "mcmc_n_iter", default_mcmc_n_iter))
    mcmc_burn <- as.integer(get_cell(sc, "mcmc_burn", default_mcmc_burn))
    mcmc_thin <- as.integer(get_cell(sc, "mcmc_thin", default_mcmc_thin))
    case_id <- sprintf("%s_seed%s_K%s", stress_case, seed, length(tau))
    fixture <- app_joint_qvp_simulate_synthetic(
      Tn = Tn,
      p = p,
      tau = tau,
      scenario = scenario,
      seed = seed,
      noise_sd = noise_sd
    )
    vb_fit <- app_joint_qvp_fit_al_vb_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = max_iter,
      tol = 1.0e-4,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      rhs_vb_inner = rhs_vb_inner
    )
    sigma_upper_bound <- max(sigma_upper_floor, sigma_upper_multiplier * max(vb_fit$sigma_mean))
    mcmc_fit <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_n_iter,
      burn = mcmc_burn,
      thin = mcmc_thin,
      seed = seed + mcmc_seed_offset,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      init = vb_fit,
      max_dense_dim = 50L,
      sigma_bounds = c(sigma_lower_bound, sigma_upper_bound)
    )
    distance <- app_joint_qvp_vb_mcmc_distance_summary(
      vb_fit = vb_fit,
      mcmc_fit = mcmc_fit,
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      Tn = Tn,
      p = p,
      K = length(fixture$tau)
    )
    distance_rows[[length(distance_rows) + 1L]] <- distance
    draw_summary <- app_joint_qvp_mcmc_draw_summary(
      mcmc_fit,
      case_id,
      stress_case,
      scenario,
      sigma_bounds = c(sigma_lower_bound, sigma_upper_bound)
    )
    max_sigma_upper_hit <- max(
      draw_summary$upper_bound_hit_fraction[draw_summary$block == "sigma"],
      na.rm = TRUE
    )
    draw_rows[[length(draw_rows) + 1L]] <- draw_summary
    vb_crossing <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, fit = "vb", stringsAsFactors = FALSE),
      vb_fit$crossing_diagnostics
    )
    mcmc_crossing <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, fit = "mcmc", stringsAsFactors = FALSE),
      mcmc_fit$crossing_diagnostics
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- rbind(vb_crossing, mcmc_crossing)
    rhs_rows[[length(rhs_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, stringsAsFactors = FALSE),
      vb_fit$rhs_prior_summary
    )
    objective_rows[[length(objective_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, stringsAsFactors = FALSE),
      vb_fit$objective_diagnostics
    )
    final_elbo_terms <- vb_fit$elbo_terms[
      vb_fit$elbo_terms$iter == max(vb_fit$elbo_terms$iter),
      ,
      drop = FALSE
    ]
    elbo_rows[[length(elbo_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, stringsAsFactors = FALSE),
      final_elbo_terms
    )
    fit_rows[[length(fit_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      seed = seed,
      mcmc_seed = seed + mcmc_seed_offset,
      vb_status = vb_fit$manifest$status[[1L]],
      vb_converged = isTRUE(vb_fit$converged),
      mcmc_status = mcmc_fit$manifest$status[[1L]],
      mcmc_init_source = mcmc_fit$init_source,
      Tn = Tn,
      p = p,
      K = length(fixture$tau),
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = noise_sd,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      vb_max_iter = max_iter,
      rhs_vb_inner = rhs_vb_inner,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_n_keep = nrow(mcmc_fit$beta_draws),
      sigma_lower_bound = sigma_lower_bound,
      sigma_upper_bound = sigma_upper_bound,
      vb_beta_l2 = sqrt(sum(vb_fit$beta_mean^2)),
      vb_sigma_mean = mean(vb_fit$sigma_mean),
      mcmc_beta_l2 = sqrt(sum(mcmc_fit$beta_mean^2)),
      mcmc_sigma_mean = mean(mcmc_fit$sigma_mean),
      final_partial_elbo = tail(vb_fit$trace$partial_elbo, 1L),
      objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
      objective_max_drop = vb_fit$objective_diagnostics$max_drop[[1L]],
      total_vb_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
      total_mcmc_crossing_pairs = sum(mcmc_fit$crossing_diagnostics$n_crossing_pairs),
      mcmc_draws_all_finite = all(draw_summary$all_finite),
      max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
      beta_normalized_distance = distance$beta_normalized_distance[[1L]],
      alpha_normalized_distance = distance$alpha_normalized_distance[[1L]],
      sigma_normalized_distance = distance$sigma_normalized_distance[[1L]],
      qhat_normalized_distance = distance$qhat_normalized_distance[[1L]],
      max_normalized_distance = distance$max_normalized_distance[[1L]],
      stringsAsFactors = FALSE
    )
    config_rows[[length(config_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      seed = seed,
      mcmc_seed = seed + mcmc_seed_offset,
      Tn = Tn,
      p = p,
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = noise_sd,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      vb_max_iter = max_iter,
      rhs_vb_inner = rhs_vb_inner,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      sigma_lower_bound = sigma_lower_bound,
      sigma_upper_bound = sigma_upper_bound,
      stringsAsFactors = FALSE
    )
  }
  fit_summary <- do.call(rbind, fit_rows)
  calibration_assessment <- app_joint_qvp_assess_mcmc_calibration(fit_summary)
  paths <- c(
    run_config = app_joint_qvp_write_csv(do.call(rbind, config_rows), file.path(out_dir, "run_config.csv")),
    calibration_thresholds = app_joint_qvp_write_csv(threshold_spec, file.path(out_dir, "calibration_thresholds.csv")),
    calibration_assessment = app_joint_qvp_write_csv(calibration_assessment, file.path(out_dir, "calibration_assessment.csv")),
    fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
    distance_summary = app_joint_qvp_write_csv(do.call(rbind, distance_rows), file.path(out_dir, "distance_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(do.call(rbind, draw_rows), file.path(out_dir, "mcmc_draw_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(do.call(rbind, crossing_rows), file.path(out_dir, "crossing_summary.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(do.call(rbind, rhs_rows), file.path(out_dir, "rhs_prior_summary.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(do.call(rbind, objective_rows), file.path(out_dir, "objective_diagnostics.csv")),
    elbo_terms = app_joint_qvp_write_csv(do.call(rbind, elbo_rows), file.path(out_dir, "elbo_terms.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_default_wide_multichain_scenarios <- function() {
  scenarios <- app_joint_qvp_default_objective_stress_scenarios()
  out <- scenarios[scenarios$stress_case == "wide_tau_parallel", , drop = FALSE]
  if (!nrow(out)) stop("Default wide_tau_parallel stress scenario is unavailable.", call. = FALSE)
  out$n_chains <- 4L
  out$mcmc_n_iter <- 300L
  out$mcmc_burn <- 150L
  out$mcmc_thin <- 10L
  out
}

app_joint_qvp_default_multichain_thresholds <- function() {
  data.frame(
    criterion = c(
      "artifact_reproducibility",
      "vb_converged",
      "warmstarted_mcmc_chains",
      "finite_chain_draws",
      "finite_pooled_distances",
      "finite_chain_to_pooled_distances",
      "fitted_crossing_pairs",
      "finite_mean_sigma_prior",
      "weak_proper_alpha_prior",
      "bounded_sigma_reference",
      "sigma_bound_hit_fraction",
      "chain_stability",
      "pooled_vb_mcmc_distance_pass",
      "pooled_vb_mcmc_distance_review"
    ),
    gate = c(
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "hard_fail",
      "documented_reference_control",
      "documented_reference_control",
      "documented_reference_control",
      "review",
      "review",
      "pass_threshold",
      "review"
    ),
    threshold = c(
      "identical_sha256_for_repeated_same_config",
      "vb_status_is_prototype_success",
      "all_init_source_are_provided",
      "all_draw_blocks_finite",
      "pooled_distance_summaries_all_finite",
      "max_chain_to_pooled_distance_finite",
      "0",
      "a_sigma = 2, b_sigma = 1",
      "alpha_prior_mean = empirical_quantile, alpha_prior_sd = 1",
      "sigma_upper = max(1, 50 * max(vb_sigma_mean))",
      "upper_bound_hit_fraction == 0 for pass",
      "max_chain_to_pooled_normalized_distance <= 5",
      "pooled_max_normalized_distance <= 5",
      "pooled_max_normalized_distance > 5"
    ),
    rationale = c(
      "Multi-chain calibration artifacts must be reproducible before informing thresholds.",
      "Wide-grid MCMC calibration should start from a converged VB state.",
      "Every MCMC reference chain must use the VB state as initialization.",
      "Reference chains cannot calibrate thresholds with non-finite draws.",
      "Pooled VB/MCMC agreement metrics must be numerically valid.",
      "Chain-to-pooled reference spread must be numerically valid.",
      "Calibration should not silently promote crossed fitted summaries.",
      "The wide-grid reference uses the calibrated finite-mean scale prior.",
      "The wide tail-grid reference uses a weak proper ordered-intercept prior to prevent unidentified AL tail-shift drift.",
      "The scale block remains bounded broadly relative to the converged VB scale.",
      "A positive bound-hit fraction indicates bound-sensitive chain behavior and remains review-only.",
      "Large chain-to-pooled spread indicates an unstable reference, even when pooled distance passes.",
      "Initial loose pooled-distance pass rule inherited from the synthetic smoke policy.",
      "Distances above the loose rule are retained for review and threshold calibration."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qvp_pool_mcmc_chains <- function(fits, Z, K, p, tau) {
  if (!length(fits)) stop("At least one MCMC fit is required for pooling.", call. = FALSE)
  beta_draws <- do.call(rbind, lapply(fits, `[[`, "beta_draws"))
  alpha_draws <- do.call(rbind, lapply(fits, `[[`, "alpha_draws"))
  sigma_draws <- do.call(rbind, lapply(fits, `[[`, "sigma_draws"))
  beta_mean <- colMeans(beta_draws)
  alpha_mean <- colMeans(alpha_draws)
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) +
    matrix(alpha_mean, nrow = nrow(Z), ncol = K, byrow = TRUE)
  list(
    beta_draws = beta_draws,
    alpha_draws = alpha_draws,
    sigma_draws = sigma_draws,
    beta_mean = beta_mean,
    alpha_mean = alpha_mean,
    sigma_mean = colMeans(sigma_draws),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    init_source = paste(sort(unique(vapply(fits, function(x) x$init_source %||% NA_character_, character(1L)))), collapse = ";")
  )
}

app_joint_qvp_chain_to_pooled_summary <- function(fits, pooled_fit, Z, case_id, stress_case, scenario, Tn, p, K) {
  rows <- lapply(seq_along(fits), function(chain_id) {
    fit <- fits[[chain_id]]
    beta_l2 <- app_joint_qvp_l2_distance(fit$beta_mean, pooled_fit$beta_mean)
    alpha_l2 <- app_joint_qvp_l2_distance(fit$alpha_mean, pooled_fit$alpha_mean)
    sigma_l2 <- app_joint_qvp_l2_distance(fit$sigma_mean, pooled_fit$sigma_mean)
    qhat_l2 <- app_joint_qvp_l2_distance(fit$qhat_mean, pooled_fit$qhat_mean)
    beta_norm <- beta_l2 / (sqrt(p * K) * (1 + sqrt(sum(pooled_fit$beta_mean^2))))
    alpha_norm <- alpha_l2 / (sqrt(K) * (1 + mean(pooled_fit$sigma_mean)))
    sigma_norm <- sigma_l2 / (sqrt(K) * (1 + mean(pooled_fit$sigma_mean)))
    qhat_norm <- qhat_l2 / (sqrt(Tn * K) * (1 + sqrt(mean(pooled_fit$qhat_mean^2))))
    data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      chain_id = chain_id,
      beta_l2_to_pooled = beta_l2,
      alpha_l2_to_pooled = alpha_l2,
      sigma_l2_to_pooled = sigma_l2,
      qhat_l2_to_pooled = qhat_l2,
      beta_normalized_to_pooled = beta_norm,
      alpha_normalized_to_pooled = alpha_norm,
      sigma_normalized_to_pooled = sigma_norm,
      qhat_normalized_to_pooled = qhat_norm,
      max_normalized_to_pooled = max(c(beta_norm, alpha_norm, sigma_norm, qhat_norm), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_assess_multichain_reference <- function(fit_summary, distance_pass = 5, chain_pass = 5) {
  if (!nrow(fit_summary)) return(data.frame())
  rows <- vector("list", nrow(fit_summary))
  for (ii in seq_len(nrow(fit_summary))) {
    fit <- fit_summary[ii, , drop = FALSE]
    finite_required <- all(is.finite(c(
      fit$vb_beta_l2,
      fit$vb_sigma_mean,
      fit$pooled_mcmc_sigma_mean,
      fit$pooled_max_normalized_distance,
      fit$max_chain_to_pooled_normalized_distance,
      fit$max_sigma_upper_bound_hit_fraction
    )))
    hard_fail <- !finite_required ||
      !isTRUE(fit$vb_converged) ||
      !isTRUE(fit$all_chains_warmstarted) ||
      !isTRUE(fit$all_chain_draws_finite) ||
      fit$total_vb_crossing_pairs > 0 ||
      fit$total_pooled_mcmc_crossing_pairs > 0
    reference_status <- if (is.finite(fit$max_sigma_upper_bound_hit_fraction) &&
        fit$max_sigma_upper_bound_hit_fraction <= 0) {
      "pass"
    } else {
      "review"
    }
    chain_status <- if (is.finite(fit$max_chain_to_pooled_normalized_distance) &&
        fit$max_chain_to_pooled_normalized_distance <= chain_pass) {
      "pass"
    } else {
      "review"
    }
    distance_status <- if (is.finite(fit$pooled_max_normalized_distance) &&
        fit$pooled_max_normalized_distance <= distance_pass) {
      "pass"
    } else {
      "review"
    }
    gate_status <- if (hard_fail) {
      "fail"
    } else if (identical(reference_status, "review") ||
        identical(chain_status, "review") ||
        identical(distance_status, "review")) {
      "review"
    } else {
      "pass"
    }
    rows[[ii]] <- data.frame(
      case_id = fit$case_id,
      stress_case = fit$stress_case,
      scenario = fit$scenario,
      implementation_status = if (hard_fail) "fail" else "pass",
      reference_status = reference_status,
      chain_stability_status = chain_status,
      distance_status = distance_status,
      gate_status = gate_status,
      pooled_max_normalized_distance = fit$pooled_max_normalized_distance,
      max_chain_to_pooled_normalized_distance = fit$max_chain_to_pooled_normalized_distance,
      max_sigma_upper_bound_hit_fraction = fit$max_sigma_upper_bound_hit_fraction,
      crossing_pairs = fit$total_vb_crossing_pairs + fit$total_pooled_mcmc_crossing_pairs,
      notes = if (hard_fail) {
        "hard multi-chain reference criterion failed"
      } else if (identical(reference_status, "review")) {
        "sigma bound hit fraction retained for reference review"
      } else if (identical(chain_status, "review")) {
        "chain-to-pooled spread retained for reference review"
      } else if (identical(distance_status, "review")) {
        "pooled VB/MCMC distance retained for threshold review"
      } else {
        "multi-chain reference gate passed"
      },
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_qvp_run_wide_multichain_mcmc_calibration <- function(
  out_dir,
  scenarios = NULL,
  default_n_chains = 4L,
  default_mcmc_n_iter = 300L,
  default_mcmc_burn = 150L,
  default_mcmc_thin = 10L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  default_a_sigma = 2,
  default_b_sigma = 1,
  default_alpha_prior_mean = "empirical_quantile",
  default_alpha_prior_sd = 1,
  sigma_lower_bound = 1.0e-8,
  sigma_upper_multiplier = 50,
  sigma_upper_floor = 1
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_wide_multichain_scenarios()
  get_cell <- function(sc, name, default) {
    if (!name %in% names(sc) || is.na(sc[[name]][[1L]])) return(default)
    sc[[name]][[1L]]
  }
  fit_rows <- list()
  chain_rows <- list()
  distance_rows <- list()
  draw_rows <- list()
  crossing_rows <- list()
  rhs_rows <- list()
  objective_rows <- list()
  elbo_rows <- list()
  config_rows <- list()
  threshold_spec <- app_joint_qvp_default_multichain_thresholds()
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, , drop = FALSE]
    tau <- app_joint_qvp_parse_tau_spec(get_cell(sc, "tau", "0.1,0.5,0.9"))
    stress_case <- as.character(get_cell(sc, "stress_case", "wide_tau_parallel"))
    scenario <- as.character(get_cell(sc, "scenario", "parallel"))
    seed <- as.integer(get_cell(sc, "seed", 20260722L))
    Tn <- as.integer(get_cell(sc, "Tn", 24L))
    p <- as.integer(get_cell(sc, "p", 3L))
    noise_sd <- as.numeric(get_cell(sc, "noise_sd", 0.05))
    kappa <- as.numeric(get_cell(sc, "kappa", 0.5))
    tau0 <- as.numeric(get_cell(sc, "tau0", 1))
    a_sigma <- as.numeric(get_cell(sc, "a_sigma", default_a_sigma))
    b_sigma <- as.numeric(get_cell(sc, "b_sigma", default_b_sigma))
    alpha_prior_mean <- get_cell(sc, "alpha_prior_mean", default_alpha_prior_mean)
    alpha_prior_sd <- as.numeric(get_cell(sc, "alpha_prior_sd", default_alpha_prior_sd))
    max_iter <- as.integer(get_cell(sc, "max_iter", 220L))
    rhs_vb_inner <- as.integer(get_cell(sc, "rhs_vb_inner", 5L))
    n_chains <- as.integer(get_cell(sc, "n_chains", default_n_chains))
    mcmc_n_iter <- as.integer(get_cell(sc, "mcmc_n_iter", default_mcmc_n_iter))
    mcmc_burn <- as.integer(get_cell(sc, "mcmc_burn", default_mcmc_burn))
    mcmc_thin <- as.integer(get_cell(sc, "mcmc_thin", default_mcmc_thin))
    if (n_chains < 2L) stop("Multi-chain calibration requires at least two chains.", call. = FALSE)
    case_id <- sprintf("%s_seed%s_K%s", stress_case, seed, length(tau))
    fixture <- app_joint_qvp_simulate_synthetic(
      Tn = Tn,
      p = p,
      tau = tau,
      scenario = scenario,
      seed = seed,
      noise_sd = noise_sd
    )
    vb_fit <- app_joint_qvp_fit_al_vb_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      max_iter = max_iter,
      tol = 1.0e-4,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      rhs_vb_inner = rhs_vb_inner
    )
    sigma_upper_bound <- max(sigma_upper_floor, sigma_upper_multiplier * max(vb_fit$sigma_mean))
    fits <- vector("list", n_chains)
    chain_draw_rows <- list()
    for (chain_id in seq_len(n_chains)) {
      chain_seed <- seed + mcmc_seed_offset + (chain_id - 1L) * chain_seed_stride
      fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
        y = fixture$y,
        Z = fixture$Z,
        tau = fixture$tau,
        n_iter = mcmc_n_iter,
        burn = mcmc_burn,
        thin = mcmc_thin,
        seed = chain_seed,
        kappa = kappa,
        tau0 = tau0,
        a_sigma = a_sigma,
        b_sigma = b_sigma,
        alpha_prior_mean = alpha_prior_mean,
        alpha_prior_sd = alpha_prior_sd,
        init = vb_fit,
        max_dense_dim = 50L,
        sigma_bounds = c(sigma_lower_bound, sigma_upper_bound)
      )
      chain_draw <- app_joint_qvp_mcmc_draw_summary(
        fits[[chain_id]],
        case_id,
        stress_case,
        scenario,
        sigma_bounds = c(sigma_lower_bound, sigma_upper_bound)
      )
      chain_draw_rows[[chain_id]] <- cbind(
        data.frame(chain_id = chain_id, chain_seed = chain_seed, stringsAsFactors = FALSE),
        chain_draw
      )
      crossing_rows[[length(crossing_rows) + 1L]] <- cbind(
        data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, fit = sprintf("chain_%s", chain_id), chain_id = chain_id, stringsAsFactors = FALSE),
        fits[[chain_id]]$crossing_diagnostics
      )
    }
    draw_summary <- do.call(rbind, chain_draw_rows)
    pooled_fit <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), p, fixture$tau)
    pooled_distance <- app_joint_qvp_vb_mcmc_distance_summary(
      vb_fit = vb_fit,
      mcmc_fit = pooled_fit,
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      Tn = Tn,
      p = p,
      K = length(fixture$tau)
    )
    chain_summary <- app_joint_qvp_chain_to_pooled_summary(
      fits = fits,
      pooled_fit = pooled_fit,
      Z = fixture$Z,
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      Tn = Tn,
      p = p,
      K = length(fixture$tau)
    )
    max_sigma_upper_hit <- max(
      draw_summary$upper_bound_hit_fraction[draw_summary$block == "sigma"],
      na.rm = TRUE
    )
    vb_crossing <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, fit = "vb", chain_id = NA_integer_, stringsAsFactors = FALSE),
      vb_fit$crossing_diagnostics
    )
    pooled_crossing <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, fit = "pooled_mcmc", chain_id = NA_integer_, stringsAsFactors = FALSE),
      pooled_fit$crossing_diagnostics
    )
    crossing_rows[[length(crossing_rows) + 1L]] <- vb_crossing
    crossing_rows[[length(crossing_rows) + 1L]] <- pooled_crossing
    rhs_rows[[length(rhs_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, stringsAsFactors = FALSE),
      vb_fit$rhs_prior_summary
    )
    objective_rows[[length(objective_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, stringsAsFactors = FALSE),
      vb_fit$objective_diagnostics
    )
    final_elbo_terms <- vb_fit$elbo_terms[
      vb_fit$elbo_terms$iter == max(vb_fit$elbo_terms$iter),
      ,
      drop = FALSE
    ]
    elbo_rows[[length(elbo_rows) + 1L]] <- cbind(
      data.frame(case_id = case_id, stress_case = stress_case, scenario = scenario, stringsAsFactors = FALSE),
      final_elbo_terms
    )
    draw_rows[[length(draw_rows) + 1L]] <- draw_summary
    distance_rows[[length(distance_rows) + 1L]] <- pooled_distance
    chain_rows[[length(chain_rows) + 1L]] <- chain_summary
    fit_rows[[length(fit_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      seed = seed,
      vb_status = vb_fit$manifest$status[[1L]],
      vb_converged = isTRUE(vb_fit$converged),
      all_chains_warmstarted = all(vapply(fits, function(x) identical(x$init_source, "provided"), logical(1L))),
      Tn = Tn,
      p = p,
      K = length(fixture$tau),
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = noise_sd,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = if (length(alpha_prior_mean) == 1L) as.character(alpha_prior_mean) else paste(alpha_prior_mean, collapse = ","),
      alpha_prior_mean_source = vb_fit$alpha_prior_mean_source,
      alpha_prior_mean_values = paste(format(vb_fit$alpha_prior_mean, digits = 8), collapse = ","),
      alpha_prior_sd = paste(format(vb_fit$alpha_prior_sd, digits = 8), collapse = ","),
      vb_max_iter = max_iter,
      rhs_vb_inner = rhs_vb_inner,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_n_keep_per_chain = nrow(fits[[1L]]$beta_draws),
      mcmc_n_keep_total = nrow(pooled_fit$beta_draws),
      sigma_lower_bound = sigma_lower_bound,
      sigma_upper_bound = sigma_upper_bound,
      vb_beta_l2 = sqrt(sum(vb_fit$beta_mean^2)),
      vb_sigma_mean = mean(vb_fit$sigma_mean),
      pooled_mcmc_beta_l2 = sqrt(sum(pooled_fit$beta_mean^2)),
      pooled_mcmc_sigma_mean = mean(pooled_fit$sigma_mean),
      final_partial_elbo = tail(vb_fit$trace$partial_elbo, 1L),
      objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
      objective_max_drop = vb_fit$objective_diagnostics$max_drop[[1L]],
      total_vb_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
      total_pooled_mcmc_crossing_pairs = sum(pooled_fit$crossing_diagnostics$n_crossing_pairs),
      all_chain_draws_finite = all(draw_summary$all_finite),
      max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
      pooled_beta_normalized_distance = pooled_distance$beta_normalized_distance[[1L]],
      pooled_alpha_normalized_distance = pooled_distance$alpha_normalized_distance[[1L]],
      pooled_sigma_normalized_distance = pooled_distance$sigma_normalized_distance[[1L]],
      pooled_qhat_normalized_distance = pooled_distance$qhat_normalized_distance[[1L]],
      pooled_max_normalized_distance = pooled_distance$max_normalized_distance[[1L]],
      max_chain_to_pooled_normalized_distance = max(chain_summary$max_normalized_to_pooled, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
    config_rows[[length(config_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      seed = seed,
      Tn = Tn,
      p = p,
      tau = paste(fixture$tau, collapse = ","),
      noise_sd = noise_sd,
      kappa = kappa,
      tau0 = tau0,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = if (length(alpha_prior_mean) == 1L) as.character(alpha_prior_mean) else paste(alpha_prior_mean, collapse = ","),
      alpha_prior_mean_source = vb_fit$alpha_prior_mean_source,
      alpha_prior_mean_values = paste(format(vb_fit$alpha_prior_mean, digits = 8), collapse = ","),
      alpha_prior_sd = paste(format(vb_fit$alpha_prior_sd, digits = 8), collapse = ","),
      vb_max_iter = max_iter,
      rhs_vb_inner = rhs_vb_inner,
      n_chains = n_chains,
      mcmc_n_iter = mcmc_n_iter,
      mcmc_burn = mcmc_burn,
      mcmc_thin = mcmc_thin,
      mcmc_seed_offset = mcmc_seed_offset,
      chain_seed_stride = chain_seed_stride,
      sigma_lower_bound = sigma_lower_bound,
      sigma_upper_bound = sigma_upper_bound,
      stringsAsFactors = FALSE
    )
  }
  fit_summary <- do.call(rbind, fit_rows)
  multichain_assessment <- app_joint_qvp_assess_multichain_reference(fit_summary)
  paths <- c(
    run_config = app_joint_qvp_write_csv(do.call(rbind, config_rows), file.path(out_dir, "run_config.csv")),
    multichain_thresholds = app_joint_qvp_write_csv(threshold_spec, file.path(out_dir, "multichain_thresholds.csv")),
    multichain_assessment = app_joint_qvp_write_csv(multichain_assessment, file.path(out_dir, "multichain_assessment.csv")),
    fit_summary = app_joint_qvp_write_csv(fit_summary, file.path(out_dir, "fit_summary.csv")),
    chain_summary = app_joint_qvp_write_csv(do.call(rbind, chain_rows), file.path(out_dir, "chain_summary.csv")),
    pooled_distance_summary = app_joint_qvp_write_csv(do.call(rbind, distance_rows), file.path(out_dir, "pooled_distance_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(do.call(rbind, draw_rows), file.path(out_dir, "mcmc_draw_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(do.call(rbind, crossing_rows), file.path(out_dir, "crossing_summary.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(do.call(rbind, rhs_rows), file.path(out_dir, "rhs_prior_summary.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(do.call(rbind, objective_rows), file.path(out_dir, "objective_diagnostics.csv")),
    elbo_terms = app_joint_qvp_write_csv(do.call(rbind, elbo_rows), file.path(out_dir, "elbo_terms.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_alpha_gap_rows <- function(
  fixture,
  vb_fit,
  pooled_fit,
  case_id,
  stress_case,
  scenario,
  alpha_prior_mean,
  alpha_prior_sd
) {
  constants <- app_joint_qvp_al_constants(fixture$tau)
  rows <- lapply(seq_along(fixture$tau), function(k) {
    alpha_draw_quantiles <- stats::quantile(
      pooled_fit$alpha_draws[, k],
      probs = c(0.05, 0.5, 0.95),
      names = FALSE,
      type = 8
    )
    data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      quantile_index = k,
      tau = fixture$tau[[k]],
      al_A = constants$A[[k]],
      al_B = constants$B[[k]],
      alpha_prior_mean = if (length(alpha_prior_mean) == 1L) as.character(alpha_prior_mean) else paste(alpha_prior_mean, collapse = ","),
      alpha_prior_sd = alpha_prior_sd,
      resolved_alpha_prior_mean = vb_fit$alpha_prior_mean[[k]],
      true_alpha = fixture$alpha[[k]],
      vb_alpha = vb_fit$alpha_mean[[k]],
      pooled_mcmc_alpha = pooled_fit$alpha_mean[[k]],
      pooled_minus_vb_alpha = pooled_fit$alpha_mean[[k]] - vb_fit$alpha_mean[[k]],
      pooled_alpha_q05 = alpha_draw_quantiles[[1L]],
      pooled_alpha_q50 = alpha_draw_quantiles[[2L]],
      pooled_alpha_q95 = alpha_draw_quantiles[[3L]],
      vb_order_gap_from_previous = if (k == 1L) NA_real_ else vb_fit$alpha_mean[[k]] - vb_fit$alpha_mean[[k - 1L]],
      pooled_order_gap_from_previous = if (k == 1L) NA_real_ else pooled_fit$alpha_mean[[k]] - pooled_fit$alpha_mean[[k - 1L]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_quantile_fit_rows <- function(fixture, fit, fit_label, case_id, stress_case, scenario, alpha_prior_sd) {
  rows <- lapply(seq_along(fixture$tau), function(k) {
    qhat <- fit$qhat_mean[, k]
    data.frame(
      case_id = case_id,
      stress_case = stress_case,
      scenario = scenario,
      fit = fit_label,
      alpha_prior_sd = alpha_prior_sd,
      quantile_index = k,
      tau = fixture$tau[[k]],
      empirical_hit_rate = mean(fixture$y <= qhat),
      hit_rate_minus_tau = mean(fixture$y <= qhat) - fixture$tau[[k]],
      mean_abs_qhat_minus_true_q = mean(abs(qhat - fixture$true_q[, k])),
      max_abs_qhat_minus_true_q = max(abs(qhat - fixture$true_q[, k])),
      qhat_mean = mean(qhat),
      qhat_sd = stats::sd(qhat),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_assess_alpha_gap_audit <- function(distance_summary, chain_summary, alpha_gap_summary) {
  rows <- lapply(seq_len(nrow(distance_summary)), function(ii) {
    dist <- distance_summary[ii, , drop = FALSE]
    chain <- chain_summary[chain_summary$case_id == dist$case_id[[1L]], , drop = FALSE]
    alpha <- alpha_gap_summary[alpha_gap_summary$case_id == dist$case_id[[1L]], , drop = FALSE]
    max_abs_alpha_gap <- max(abs(alpha$pooled_minus_vb_alpha), na.rm = TRUE)
    max_chain_spread <- max(chain$max_normalized_to_pooled, na.rm = TRUE)
    finite_required <- all(is.finite(c(
      dist$max_normalized_distance,
      dist$alpha_normalized_distance,
      max_abs_alpha_gap,
      max_chain_spread
    )))
    distance_status <- if (finite_required && dist$max_normalized_distance[[1L]] <= 5) "pass" else "review"
    alpha_status <- if (finite_required && dist$alpha_normalized_distance[[1L]] <= 5) "pass" else "review"
    chain_status <- if (finite_required && max_chain_spread <= 5) "pass" else "review"
    gate_status <- if (!finite_required) {
      "fail"
    } else if (identical(distance_status, "pass") &&
        identical(alpha_status, "pass") &&
        identical(chain_status, "pass")) {
      "pass"
    } else {
      "review"
    }
    prior_sd <- alpha$alpha_prior_sd[[1L]]
    issue_class <- if (!is.finite(dist$alpha_normalized_distance[[1L]])) {
      "nonfinite_alpha_gap"
    } else if (dist$alpha_normalized_distance[[1L]] > 5 && max_chain_spread <= 5) {
      "alpha_drift_not_chain_noise"
    } else if (is.infinite(prior_sd)) {
      "no_prior_short_reference_stable"
    } else if (dist$max_normalized_distance[[1L]] <= 5 && dist$alpha_normalized_distance[[1L]] <= 5) {
      "alpha_gap_stabilized"
    } else {
      "mixed_gap"
    }
    data.frame(
      case_id = dist$case_id,
      stress_case = dist$stress_case,
      scenario = dist$scenario,
      alpha_prior_sd = alpha$alpha_prior_sd[[1L]],
      distance_status = distance_status,
      alpha_gap_status = alpha_status,
      chain_stability_status = chain_status,
      gate_status = gate_status,
      issue_class = issue_class,
      max_normalized_distance = dist$max_normalized_distance,
      alpha_normalized_distance = dist$alpha_normalized_distance,
      max_abs_alpha_gap = max_abs_alpha_gap,
      max_chain_to_pooled_normalized_distance = max_chain_spread,
      notes = if (identical(issue_class, "alpha_drift_not_chain_noise")) {
        "pooled reference is stable, but alpha dominates the VB/MCMC gap"
      } else if (identical(issue_class, "no_prior_short_reference_stable")) {
        "no-prior short reference did not drift past the review threshold"
      } else if (identical(issue_class, "alpha_gap_stabilized")) {
        "weak proper alpha prior stabilizes the wide-tail reference"
      } else {
        "retain for audit review"
      },
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_joint_qvp_alpha_prior_sd_label <- function(x) {
  if (is.infinite(x)) return("inf")
  gsub("[^A-Za-z0-9]+", "p", format(x, scientific = FALSE, trim = TRUE))
}

app_joint_qvp_run_wide_alpha_gap_audit <- function(
  out_dir,
  scenarios = NULL,
  alpha_prior_sds = c(Inf, 10, 5, 2, 1, 0.5),
  default_n_chains = 2L,
  default_mcmc_n_iter = 120L,
  default_mcmc_burn = 60L,
  default_mcmc_thin = 5L,
  mcmc_seed_offset = 1000L,
  chain_seed_stride = 10000L,
  default_a_sigma = 2,
  default_b_sigma = 1,
  finite_alpha_prior_mean = "empirical_quantile"
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- scenarios %||% app_joint_qvp_default_wide_multichain_scenarios()
  get_cell <- function(sc, name, default) {
    if (!name %in% names(sc) || is.na(sc[[name]][[1L]])) return(default)
    sc[[name]][[1L]]
  }
  config_rows <- list()
  distance_rows <- list()
  chain_rows <- list()
  alpha_rows <- list()
  fit_rows <- list()
  for (ii in seq_len(nrow(scenarios))) {
    sc <- scenarios[ii, , drop = FALSE]
    tau <- app_joint_qvp_parse_tau_spec(get_cell(sc, "tau", "0.1,0.5,0.9"))
    stress_case <- as.character(get_cell(sc, "stress_case", "wide_tau_parallel"))
    scenario <- as.character(get_cell(sc, "scenario", "parallel"))
    seed <- as.integer(get_cell(sc, "seed", 20260722L))
    Tn <- as.integer(get_cell(sc, "Tn", 24L))
    p <- as.integer(get_cell(sc, "p", 3L))
    noise_sd <- as.numeric(get_cell(sc, "noise_sd", 0.05))
    kappa <- as.numeric(get_cell(sc, "kappa", 0.5))
    tau0 <- as.numeric(get_cell(sc, "tau0", 1))
    a_sigma <- as.numeric(get_cell(sc, "a_sigma", default_a_sigma))
    b_sigma <- as.numeric(get_cell(sc, "b_sigma", default_b_sigma))
    max_iter <- as.integer(get_cell(sc, "max_iter", 220L))
    rhs_vb_inner <- as.integer(get_cell(sc, "rhs_vb_inner", 5L))
    n_chains <- as.integer(get_cell(sc, "n_chains", default_n_chains))
    mcmc_n_iter <- as.integer(get_cell(sc, "mcmc_n_iter", default_mcmc_n_iter))
    mcmc_burn <- as.integer(get_cell(sc, "mcmc_burn", default_mcmc_burn))
    mcmc_thin <- as.integer(get_cell(sc, "mcmc_thin", default_mcmc_thin))
    fixture <- app_joint_qvp_simulate_synthetic(
      Tn = Tn,
      p = p,
      tau = tau,
      scenario = scenario,
      seed = seed,
      noise_sd = noise_sd
    )
    for (alpha_prior_sd in as.numeric(alpha_prior_sds)) {
      alpha_prior_mean <- if (is.infinite(alpha_prior_sd)) NULL else finite_alpha_prior_mean
      prior_label <- app_joint_qvp_alpha_prior_sd_label(alpha_prior_sd)
      case_id <- sprintf("%s_seed%s_K%s_alpha_sd_%s", stress_case, seed, length(tau), prior_label)
      vb_fit <- app_joint_qvp_fit_al_vb_tiny(
        y = fixture$y,
        Z = fixture$Z,
        tau = fixture$tau,
        max_iter = max_iter,
        tol = 1.0e-4,
        kappa = kappa,
        tau0 = tau0,
        a_sigma = a_sigma,
        b_sigma = b_sigma,
        alpha_prior_mean = alpha_prior_mean,
        alpha_prior_sd = alpha_prior_sd,
        rhs_vb_inner = rhs_vb_inner
      )
      sigma_upper_bound <- max(1, 50 * max(vb_fit$sigma_mean))
      fits <- vector("list", n_chains)
      for (chain_id in seq_len(n_chains)) {
        chain_seed <- seed + mcmc_seed_offset + (chain_id - 1L) * chain_seed_stride
        fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
          y = fixture$y,
          Z = fixture$Z,
          tau = fixture$tau,
          n_iter = mcmc_n_iter,
          burn = mcmc_burn,
          thin = mcmc_thin,
          seed = chain_seed,
          kappa = kappa,
          tau0 = tau0,
          a_sigma = a_sigma,
          b_sigma = b_sigma,
          alpha_prior_mean = alpha_prior_mean,
          alpha_prior_sd = alpha_prior_sd,
          init = vb_fit,
          max_dense_dim = 50L,
          sigma_bounds = c(1.0e-8, sigma_upper_bound)
        )
      }
      pooled_fit <- app_joint_qvp_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), p, fixture$tau)
      distance_rows[[length(distance_rows) + 1L]] <- app_joint_qvp_vb_mcmc_distance_summary(
        vb_fit = vb_fit,
        mcmc_fit = pooled_fit,
        case_id = case_id,
        stress_case = stress_case,
        scenario = scenario,
        Tn = Tn,
        p = p,
        K = length(fixture$tau)
      )
      chain_rows[[length(chain_rows) + 1L]] <- app_joint_qvp_chain_to_pooled_summary(
        fits = fits,
        pooled_fit = pooled_fit,
        Z = fixture$Z,
        case_id = case_id,
        stress_case = stress_case,
        scenario = scenario,
        Tn = Tn,
        p = p,
        K = length(fixture$tau)
      )
      alpha_rows[[length(alpha_rows) + 1L]] <- app_joint_qvp_alpha_gap_rows(
        fixture = fixture,
        vb_fit = vb_fit,
        pooled_fit = pooled_fit,
        case_id = case_id,
        stress_case = stress_case,
        scenario = scenario,
        alpha_prior_mean = alpha_prior_mean %||% "none",
        alpha_prior_sd = alpha_prior_sd
      )
      fit_rows[[length(fit_rows) + 1L]] <- rbind(
        app_joint_qvp_quantile_fit_rows(fixture, vb_fit, "vb", case_id, stress_case, scenario, alpha_prior_sd),
        app_joint_qvp_quantile_fit_rows(fixture, pooled_fit, "pooled_mcmc", case_id, stress_case, scenario, alpha_prior_sd)
      )
      config_rows[[length(config_rows) + 1L]] <- data.frame(
        case_id = case_id,
        stress_case = stress_case,
        scenario = scenario,
        seed = seed,
        Tn = Tn,
        p = p,
        tau = paste(fixture$tau, collapse = ","),
        noise_sd = noise_sd,
        kappa = kappa,
        tau0 = tau0,
        a_sigma = a_sigma,
        b_sigma = b_sigma,
        alpha_prior_mean = alpha_prior_mean %||% "none",
        alpha_prior_sd = alpha_prior_sd,
        vb_max_iter = max_iter,
        rhs_vb_inner = rhs_vb_inner,
        n_chains = n_chains,
        mcmc_n_iter = mcmc_n_iter,
        mcmc_burn = mcmc_burn,
        mcmc_thin = mcmc_thin,
        mcmc_seed_offset = mcmc_seed_offset,
        chain_seed_stride = chain_seed_stride,
        sigma_upper_bound = sigma_upper_bound,
        stringsAsFactors = FALSE
      )
    }
  }
  distance_summary <- do.call(rbind, distance_rows)
  chain_summary <- do.call(rbind, chain_rows)
  alpha_gap_summary <- do.call(rbind, alpha_rows)
  quantile_fit_summary <- do.call(rbind, fit_rows)
  audit_assessment <- app_joint_qvp_assess_alpha_gap_audit(distance_summary, chain_summary, alpha_gap_summary)
  paths <- c(
    run_config = app_joint_qvp_write_csv(do.call(rbind, config_rows), file.path(out_dir, "run_config.csv")),
    audit_assessment = app_joint_qvp_write_csv(audit_assessment, file.path(out_dir, "audit_assessment.csv")),
    fit_distance_summary = app_joint_qvp_write_csv(distance_summary, file.path(out_dir, "fit_distance_summary.csv")),
    chain_stability_summary = app_joint_qvp_write_csv(chain_summary, file.path(out_dir, "chain_stability_summary.csv")),
    alpha_gap_summary = app_joint_qvp_write_csv(alpha_gap_summary, file.path(out_dir, "alpha_gap_summary.csv")),
    quantile_fit_summary = app_joint_qvp_write_csv(quantile_fit_summary, file.path(out_dir, "quantile_fit_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv"))
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_path), manifest = manifest)
}

app_joint_qvp_fit_al_vb_tiny <- function(
  y,
  Z,
  tau,
  max_iter = 100L,
  tol = 1.0e-5,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 0.1,
  b_sigma = 0.1,
  alpha_prior_mean = NULL,
  alpha_prior_sd = Inf,
  alpha_min_spacing = 0,
  max_dense_dim = 300L,
  rhs_vb_inner = 5L
) {
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  max_iter <- as.integer(max_iter)
  if (max_iter <= 0L || !is.finite(tol) || tol <= 0) stop("Invalid VB controls.", call. = FALSE)
  if (!is.finite(kappa) || kappa <= 0) stop("kappa must be positive.", call. = FALSE)
  rhs_vb_inner <- as.integer(rhs_vb_inner)
  if (rhs_vb_inner <= 0L) stop("rhs_vb_inner must be positive.", call. = FALSE)
  if (K * p > max_dense_dim) {
    stop("Tiny AL-VB prototype stores dense q(beta) covariance; reduce dimensions or raise max_dense_dim deliberately.", call. = FALSE)
  }
  constants <- app_joint_qvp_al_constants(tau)
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, alpha_prior_mean, alpha_prior_sd)
  rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = tau0, zeta2 = zeta2)
  prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
  prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
  beta_mean <- rep(0, K * p)
  beta_cov <- solve(as.matrix(prior$P_beta + Matrix::Diagonal(K * p) * 1.0e-8))
  alpha <- sort(as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8)))
  sigma_shape <- rep(a_sigma + 1.5 * kappa * Tn, K)
  sigma_rate <- rep(b_sigma + max(stats::var(y), 1.0e-3), K)
  v_mean <- matrix(1, nrow = Tn, ncol = K)
  v_inv_mean <- matrix(1, nrow = Tn, ncol = K)
  trace <- vector("list", max_iter)
  monitor_trace <- vector("list", max_iter)
  elbo_trace <- vector("list", max_iter)
  sigma_trace <- matrix(NA_real_, nrow = max_iter, ncol = K)
  colnames(sigma_trace) <- paste0("tau_", seq_len(K))
  rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
  converged <- FALSE
  for (iter in seq_len(max_iter)) {
    beta_old <- beta_mean
    sigma_inv <- sigma_shape / sigma_rate
    precision <- prior$P_beta
    rhs <- rep(0, K * p)
    for (k in seq_len(K)) {
      idx_beta <- ((k - 1L) * p + 1L):(k * p)
      w <- kappa * sigma_inv[[k]] * v_inv_mean[, k] / constants$B[[k]]
      precision[idx_beta, idx_beta] <- precision[idx_beta, idx_beta] + Matrix::t(Matrix::Matrix(Z, sparse = TRUE)) %*% Matrix::Diagonal(x = w) %*% Matrix::Matrix(Z, sparse = TRUE)
      rhs[idx_beta] <- as.numeric(Matrix::t(Matrix::Matrix(Z, sparse = TRUE)) %*%
        (kappa * sigma_inv[[k]] / constants$B[[k]] *
           (v_inv_mean[, k] * (y - alpha[[k]]) - constants$A[[k]])))
    }
    precision <- Matrix::forceSymmetric(precision)
    beta_mean <- as.numeric(Matrix::solve(precision, rhs))
    beta_cov <- solve(as.matrix(precision))
    beta_mat <- app_joint_qvp_beta_matrix(beta_mean, K, p)
    fitted_no_alpha <- Z %*% beta_mat
    beta_var_by_k <- lapply(seq_len(K), function(k) {
      idx_beta <- ((k - 1L) * p + 1L):(k * p)
      rowSums((Z %*% beta_cov[idx_beta, idx_beta, drop = FALSE]) * Z)
    })
    for (k in seq_len(K)) {
      w <- kappa * sigma_inv[[k]] * v_inv_mean[, k] / constants$B[[k]]
      cA <- kappa * sigma_inv[[k]] * constants$A[[k]] / constants$B[[k]]
      prior_prec <- alpha_prior$precision[[k]]
      mean_alpha <- (sum(w * (y - fitted_no_alpha[, k]) - cA) +
        prior_prec * alpha_prior$mean[[k]]) / (sum(w) + prior_prec)
      lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + alpha_min_spacing
      upper <- if (k == K) Inf else alpha[[k + 1L]] - alpha_min_spacing
      alpha[[k]] <- min(max(mean_alpha, lower), upper)
    }
    for (k in seq_len(K)) {
      r_mean <- y - alpha[[k]] - fitted_no_alpha[, k]
      r2_mean <- r_mean^2 + beta_var_by_k[[k]]
      chi <- kappa * sigma_inv[[k]] * r2_mean / constants$B[[k]]
      psi <- kappa * sigma_inv[[k]] * (constants$A[[k]]^2 / constants$B[[k]] + 2)
	      lambda_v <- 1 - kappa / 2
	      v_mean[, k] <- app_joint_qvp_gig_moment(lambda_v, chi, psi, 1)
	      v_inv_mean[, k] <- app_joint_qvp_gig_moment(lambda_v, chi, psi, -1)
	      sigma_rate[[k]] <- b_sigma + kappa * (
	        sum(v_mean[, k]) +
	          0.5 / constants$B[[k]] * sum(r2_mean * v_inv_mean[, k] -
	            2 * constants$A[[k]] * r_mean + constants$A[[k]]^2 * v_mean[, k])
	      )
	    }
	    rhs_update <- app_joint_qvp_update_rhs_vb_state(
	      rhs_state = rhs_state,
	      beta_mean = beta_mean,
	      beta_cov = beta_cov,
	      K = K,
	      p = p,
	      n_inner = rhs_vb_inner
	    )
	    rhs_state <- rhs_update$state
	    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
	    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
	    rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
	    rhs_elbo_terms <- app_joint_qvp_rhs_vb_elbo_terms(rhs_state, K, p)
	    prior_quadratic <- 0.5 * app_joint_qvp_beta_prior_quadratic(beta_mean, beta_cov, prior$P_beta)
	    beta_logdet <- app_joint_qvp_beta_logdet(beta_cov)
	    beta_entropy_logdet <- 0.5 * beta_logdet
	    data_terms <- app_joint_qvp_al_vb_data_accounting(
	      y = y,
	      Z = Z,
	      beta_mean = beta_mean,
	      beta_cov = beta_cov,
	      alpha = alpha,
	      sigma_shape = sigma_shape,
	      sigma_rate = sigma_rate,
	      v_mean = v_mean,
	      v_inv_mean = v_inv_mean,
	      constants = constants,
	      kappa = kappa
	    )
	    elbo_terms <- app_joint_qvp_al_vb_partial_elbo_terms(
	      iter = iter,
	      data_terms = data_terms,
	      rhs_terms = rhs_elbo_terms,
	      prior_quadratic = prior_quadratic,
	      beta_logdet = beta_logdet,
	      beta_dim = K * p,
	      sigma_shape = sigma_shape,
	      sigma_rate = sigma_rate,
	      a_sigma = a_sigma,
	      b_sigma = b_sigma
	    )
	    partial_elbo <- app_joint_qvp_partial_elbo(elbo_terms)
	    monitor_terms <- c(
	      likelihood_quadratic = data_terms$likelihood_quadratic,
	      latent_linear = data_terms$latent_rate,
	      prior_quadratic = prior_quadratic,
	      beta_entropy_logdet = beta_entropy_logdet
	    )
	    monitor_trace[[iter]] <- app_joint_qvp_monitor_row(iter, monitor_terms)
		    elbo_trace[[iter]] <- elbo_terms
		    max_beta_change <- max(abs(beta_mean - beta_old))
		    monitor <- -data_terms$likelihood_quadratic - data_terms$latent_rate - prior_quadratic + beta_entropy_logdet
        sigma_trace[iter, ] <- sigma_rate / pmax(sigma_shape - 1, .Machine$double.eps)
		    trace[[iter]] <- data.frame(
	      iter = iter,
	      max_beta_change = max_beta_change,
	      max_sigma_mean = max(sigma_rate / pmax(sigma_shape - 1, .Machine$double.eps)),
	      rhs_mean_precision = mean(rhs_summary$mean_precision),
	      rhs_max_precision = max(rhs_summary$max_precision),
	      monitor = monitor,
	      partial_elbo = partial_elbo,
	      stringsAsFactors = FALSE
	    )
		    if (max_beta_change < tol) {
		      converged <- TRUE
		      trace <- trace[seq_len(iter)]
		      monitor_trace <- monitor_trace[seq_len(iter)]
		      elbo_trace <- elbo_trace[seq_len(iter)]
          sigma_trace <- sigma_trace[seq_len(iter), , drop = FALSE]
		      break
		    }
		  }
	  sigma_mean <- sigma_rate / pmax(sigma_shape - 1, .Machine$double.eps)
	  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) +
	    matrix(alpha, nrow = Tn, ncol = K, byrow = TRUE)
	  trace_out <- do.call(rbind, trace)
	  objective_diagnostics <- app_joint_qvp_objective_diagnostics(
	    trace = trace_out,
	    value_col = "partial_elbo",
	    objective_label = "al_vb_rhs_accounted_partial_elbo",
	    tolerance = 1.0e-8,
	    approximation_status = "rhs_log_precision_approx_alpha_point"
	  )
	  out <- list(
	    beta_mean = beta_mean,
	    beta_cov = beta_cov,
	    alpha_mean = alpha,
	    sigma_mean = sigma_mean,
	    sigma_shape = sigma_shape,
	    sigma_rate = sigma_rate,
	    v_mean = v_mean,
	    v_inv_mean = v_inv_mean,
	    rhs_state = rhs_state,
	    rhs_prior_summary = rhs_summary,
	    rhs_elbo_terms = rhs_elbo_terms,
	    qhat_mean = qhat_mean,
	    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
	    trace = trace_out,
      sigma_trace = sigma_trace,
	    monitor_terms = do.call(rbind, monitor_trace),
	    elbo_terms = do.call(rbind, elbo_trace),
	    objective_diagnostics = objective_diagnostics,
	    monitor_label = "al_vb_coordinate_monitor",
	    elbo_label = "al_vb_rhs_accounted_elbo_missing_alpha_entropy_log_precision_approx",
    converged = converged,
    tau = tau,
    kappa = kappa,
    alpha_prior_mean = alpha_prior$mean,
    alpha_prior_sd = alpha_prior$sd,
    alpha_prior_mean_source = alpha_prior$mean_source,
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("joint_qvp_al_vb_tiny_%s", format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau,
      kappa = kappa,
      likelihood = "al",
      inference = "vb_tiny",
      seed = NA_integer_,
      status = if (converged) "prototype_success" else "prototype_max_iter"
    )
  )
  class(out) <- c("joint_qvp_qdesn_vb_fit", "list")
  out
}

app_joint_qvp_truncnorm_positive_moments <- function(mean, sd) {
  mean <- as.numeric(mean)
  sd <- as.numeric(sd)
  n <- max(length(mean), length(sd))
  mean <- rep(mean, length.out = n)
  sd <- rep(sd, length.out = n)
  if (any(!is.finite(mean)) || any(!is.finite(sd)) || any(sd <= 0)) {
    stop("Truncated-normal moments require finite means and positive standard deviations.", call. = FALSE)
  }
  a <- -mean / sd
  tail <- stats::pnorm(a, lower.tail = FALSE)
  ratio <- stats::dnorm(a) / tail
  bad <- !is.finite(ratio)
  if (any(bad)) {
    aa <- pmax(a[bad], 1.0)
    ratio[bad] <- aa + 1 / aa
  }
  out_mean <- mean + sd * ratio
  out_var <- sd^2 * pmax(1 + a * ratio - ratio^2, 0)
  list(mean = out_mean, second = out_var + out_mean^2)
}

app_joint_qvp_fit_exal_vb_ld_tiny <- function(
  y,
  Z,
  tau,
  max_iter = 100L,
  tol = 1.0e-5,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 0.1,
  b_sigma = 0.1,
  alpha_prior_mean = NULL,
  alpha_prior_sd = Inf,
  gamma_init = NULL,
  alpha_min_spacing = 0,
  max_dense_dim = 300L,
  init = NULL,
  rhs_vb_inner = 5L
) {
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  max_iter <- as.integer(max_iter)
  if (max_iter <= 0L || !is.finite(tol) || tol <= 0) stop("Invalid VB controls.", call. = FALSE)
  if (!is.finite(kappa) || kappa <= 0) stop("kappa must be positive.", call. = FALSE)
  rhs_vb_inner <- as.integer(rhs_vb_inner)
  if (rhs_vb_inner <= 0L) stop("rhs_vb_inner must be positive.", call. = FALSE)
  if (K * p > max_dense_dim) {
    stop("Tiny exAL-VB-LD prototype stores dense q(beta) covariance; reduce dimensions or raise max_dense_dim deliberately.", call. = FALSE)
  }
  init <- app_joint_qvp_normalize_init(init, K, p)
  if (is.null(init)) {
    al_init <- app_joint_qvp_fit_al_vb_tiny(
      y = y,
      Z = Z,
      tau = tau,
      max_iter = min(max_iter, 25L),
      tol = tol,
      kappa = kappa,
      tau0 = tau0,
      zeta2 = zeta2,
      a_sigma = a_sigma,
      b_sigma = b_sigma,
      alpha_prior_mean = alpha_prior_mean,
      alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = alpha_min_spacing,
      max_dense_dim = max_dense_dim,
      rhs_vb_inner = rhs_vb_inner
    )
    init <- app_joint_qvp_normalize_init(al_init, K, p)
  }
  gamma <- init$gamma %||% if (is.null(gamma_init)) app_joint_qvp_default_gamma(tau) else app_joint_qvp_check_gamma(tau, gamma_init)
  gamma <- app_joint_qvp_check_gamma(tau, gamma)
  support <- app_joint_qvp_exal_support(tau)
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, alpha_prior_mean, alpha_prior_sd)
  rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = tau0, zeta2 = zeta2)
  prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
  prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
  beta_mean <- init$beta %||% rep(0, K * p)
  beta_cov <- solve(as.matrix(prior$P_beta + Matrix::Diagonal(K * p) * 1.0e-8))
  alpha <- init$alpha %||% sort(as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8)))
  sigma_mean <- init$sigma %||% rep(max(stats::mad(y), 1.0e-3), K)
  sigma_inv_mean <- 1 / sigma_mean
  v_mean <- matrix(1, nrow = Tn, ncol = K)
  v_inv_mean <- matrix(1, nrow = Tn, ncol = K)
  s_mean <- matrix(sqrt(2 / pi), nrow = Tn, ncol = K)
  s2_mean <- matrix(1, nrow = Tn, ncol = K)
  trace <- vector("list", max_iter)
  monitor_trace <- vector("list", max_iter)
  gamma_trace <- matrix(NA_real_, nrow = max_iter, ncol = K)
  sigma_trace <- matrix(NA_real_, nrow = max_iter, ncol = K)
  colnames(gamma_trace) <- colnames(sigma_trace) <- paste0("tau_", seq_len(K))
  rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
  converged <- FALSE
  for (iter in seq_len(max_iter)) {
    beta_old <- beta_mean
    gamma_old <- gamma
    sigma_old <- sigma_mean
    constants <- app_joint_qvp_exal_constants(tau, gamma)
    precision <- prior$P_beta
    rhs <- rep(0, K * p)
    for (k in seq_len(K)) {
      idx_beta <- ((k - 1L) * p + 1L):(k * p)
      w <- kappa * sigma_inv_mean[[k]] * v_inv_mean[, k] / constants$B[[k]]
      shifted_y <- y - alpha[[k]] - constants$lambda[[k]] * sigma_mean[[k]] * s_mean[, k]
      precision[idx_beta, idx_beta] <- precision[idx_beta, idx_beta] + Matrix::t(Matrix::Matrix(Z, sparse = TRUE)) %*% Matrix::Diagonal(x = w) %*% Matrix::Matrix(Z, sparse = TRUE)
      rhs[idx_beta] <- as.numeric(Matrix::t(Matrix::Matrix(Z, sparse = TRUE)) %*%
        (kappa * sigma_inv_mean[[k]] / constants$B[[k]] *
           (v_inv_mean[, k] * shifted_y - constants$A[[k]])))
    }
    precision <- Matrix::forceSymmetric(precision)
    beta_mean <- as.numeric(Matrix::solve(precision, rhs))
    beta_cov <- solve(as.matrix(precision))
    beta_mat <- app_joint_qvp_beta_matrix(beta_mean, K, p)
    fitted_no_alpha <- Z %*% beta_mat
    beta_var_by_k <- lapply(seq_len(K), function(k) {
      idx_beta <- ((k - 1L) * p + 1L):(k * p)
      rowSums((Z %*% beta_cov[idx_beta, idx_beta, drop = FALSE]) * Z)
    })
    for (k in seq_len(K)) {
      w <- kappa * sigma_inv_mean[[k]] * v_inv_mean[, k] / constants$B[[k]]
      shifted <- y - fitted_no_alpha[, k] - constants$lambda[[k]] * sigma_mean[[k]] * s_mean[, k]
      cA <- kappa * sigma_inv_mean[[k]] * constants$A[[k]] / constants$B[[k]]
      prior_prec <- alpha_prior$precision[[k]]
      alpha_prec <- sum(w) + prior_prec
      mean_alpha <- (sum(w * shifted - cA) + prior_prec * alpha_prior$mean[[k]]) / alpha_prec
      lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + alpha_min_spacing
      upper <- if (k == K) Inf else alpha[[k + 1L]] - alpha_min_spacing
      if (lower >= upper) stop("Ordered intercept bounds collapsed.", call. = FALSE)
      alpha[[k]] <- min(max(mean_alpha, lower), upper)
    }
    likelihood_quadratic <- 0
    latent_linear <- 0
    positive_shift_quadratic <- 0
    for (k in seq_len(K)) {
      r_mean <- y - alpha[[k]] - fitted_no_alpha[, k]
      r2_mean <- r_mean^2 + beta_var_by_k[[k]]
      centered_s2 <- r2_mean -
        2 * constants$lambda[[k]] * sigma_mean[[k]] * r_mean * s_mean[, k] +
        constants$lambda[[k]]^2 * sigma_mean[[k]]^2 * s2_mean[, k]
      chi_v <- kappa * pmax(centered_s2, .Machine$double.eps) * sigma_inv_mean[[k]] / constants$B[[k]]
      psi_v <- kappa * sigma_inv_mean[[k]] * (constants$A[[k]]^2 / constants$B[[k]] + 2)
      lambda_v <- 1 - kappa / 2
      v_mean[, k] <- app_joint_qvp_gig_moment(lambda_v, chi_v, psi_v, 1)
      v_inv_mean[, k] <- app_joint_qvp_gig_moment(lambda_v, chi_v, psi_v, -1)

      prec_s <- kappa * (1 + sigma_mean[[k]] * constants$lambda[[k]]^2 * v_inv_mean[, k] / constants$B[[k]])
      linear_s <- kappa * constants$lambda[[k]] *
        (r_mean * v_inv_mean[, k] - constants$A[[k]]) / constants$B[[k]]
      tn_moments <- app_joint_qvp_truncnorm_positive_moments(
        mean = linear_s / prec_s,
        sd = sqrt(1 / prec_s)
      )
      s_mean[, k] <- tn_moments$mean
      s2_mean[, k] <- tn_moments$second

      chi_sigma <- 2 * b_sigma + 2 * kappa * sum(v_mean[, k]) +
        kappa / constants$B[[k]] * sum(
          r2_mean * v_inv_mean[, k] -
            2 * constants$A[[k]] * r_mean +
            constants$A[[k]]^2 * v_mean[, k]
        )
      psi_sigma <- kappa * constants$lambda[[k]]^2 / constants$B[[k]] *
        sum(s2_mean[, k] * v_inv_mean[, k])
      lambda_sigma <- -a_sigma - 1.5 * kappa * Tn
      sigma_mean[[k]] <- app_joint_qvp_gig_moment(lambda_sigma, chi_sigma, max(psi_sigma, .Machine$double.eps), 1)
      sigma_inv_mean[[k]] <- app_joint_qvp_gig_moment(lambda_sigma, chi_sigma, max(psi_sigma, .Machine$double.eps), -1)

      gamma_objective <- function(g) {
        cst <- tryCatch(app_joint_qvp_exal_constants(tau[[k]], g), error = function(e) NULL)
        if (is.null(cst)) return(-Inf)
        quad <- r2_mean * v_inv_mean[, k] -
          2 * cst$lambda[[1L]] * sigma_mean[[k]] * r_mean * s_mean[, k] * v_inv_mean[, k] +
          cst$lambda[[1L]]^2 * sigma_mean[[k]]^2 * s2_mean[, k] * v_inv_mean[, k] -
          2 * cst$A[[1L]] * (r_mean - cst$lambda[[1L]] * sigma_mean[[k]] * s_mean[, k]) +
          cst$A[[1L]]^2 * v_mean[, k]
        val <- -0.5 * kappa * sum(log(cst$B[[1L]]) + quad / (cst$B[[1L]] * sigma_mean[[k]]))
        if (is.finite(val)) val else -Inf
      }
      opt <- stats::optimize(
        f = gamma_objective,
        interval = c(support$lower[[k]] + 1.0e-8, support$upper[[k]] - 1.0e-8),
        maximum = TRUE
      )
      gamma[[k]] <- opt$maximum
      likelihood_quadratic <- likelihood_quadratic + 0.5 * kappa *
        sum(centered_s2 * sigma_inv_mean[[k]] * v_inv_mean[, k]) / constants$B[[k]]
      latent_linear <- latent_linear + kappa * sum(v_mean[, k])
      positive_shift_quadratic <- positive_shift_quadratic + 0.5 * kappa * sum(s2_mean[, k])
    }
    rhs_update <- app_joint_qvp_update_rhs_vb_state(
      rhs_state = rhs_state,
      beta_mean = beta_mean,
      beta_cov = beta_cov,
      K = K,
      p = p,
      n_inner = rhs_vb_inner
    )
    rhs_state <- rhs_update$state
    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
    rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
    prior_quadratic <- 0.5 * app_joint_qvp_beta_prior_quadratic(beta_mean, beta_cov, prior$P_beta)
    beta_entropy_logdet <- 0.5 * app_joint_qvp_beta_logdet(beta_cov)
    monitor_terms <- c(
      likelihood_quadratic = likelihood_quadratic,
      latent_linear = latent_linear,
      positive_shift_quadratic = positive_shift_quadratic,
      prior_quadratic = prior_quadratic,
      beta_entropy_logdet = beta_entropy_logdet
    )
    monitor_trace[[iter]] <- app_joint_qvp_monitor_row(iter, monitor_terms)
    max_beta_change <- max(abs(beta_mean - beta_old))
    max_gamma_change <- max(abs(gamma - gamma_old))
    max_sigma_change <- max(abs(sigma_mean - sigma_old))
    monitor <- -likelihood_quadratic - latent_linear - positive_shift_quadratic -
      prior_quadratic + beta_entropy_logdet
    gamma_trace[iter, ] <- gamma
    sigma_trace[iter, ] <- sigma_mean
    trace[[iter]] <- data.frame(
      iter = iter,
      max_beta_change = max_beta_change,
      max_gamma_change = max_gamma_change,
      max_sigma_change = max_sigma_change,
      rhs_mean_precision = mean(rhs_summary$mean_precision),
      rhs_max_precision = max(rhs_summary$max_precision),
      monitor = monitor,
      stringsAsFactors = FALSE
    )
    if (max(max_beta_change, max_gamma_change, max_sigma_change) < tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      monitor_trace <- monitor_trace[seq_len(iter)]
      gamma_trace <- gamma_trace[seq_len(iter), , drop = FALSE]
      sigma_trace <- sigma_trace[seq_len(iter), , drop = FALSE]
      break
    }
  }
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) +
    matrix(alpha, nrow = Tn, ncol = K, byrow = TRUE)
  out <- list(
    beta_mean = beta_mean,
    beta_cov = beta_cov,
    alpha_mean = alpha,
    sigma_mean = sigma_mean,
    sigma_inv_mean = sigma_inv_mean,
    gamma_mean = gamma,
    v_mean = v_mean,
    v_inv_mean = v_inv_mean,
    s_mean = s_mean,
    s2_mean = s2_mean,
    rhs_state = rhs_state,
    rhs_prior_summary = rhs_summary,
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    trace = do.call(rbind, trace),
    gamma_trace = gamma_trace,
    sigma_trace = sigma_trace,
    monitor_terms = do.call(rbind, monitor_trace),
    converged = converged,
    tau = tau,
    kappa = kappa,
    monitor_label = "approximate_vb_ld_coordinate_monitor",
    alpha_prior_mean = alpha_prior$mean,
    alpha_prior_sd = alpha_prior$sd,
    alpha_prior_mean_source = alpha_prior$mean_source,
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("joint_qvp_exal_vb_ld_tiny_%s", format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau,
      kappa = kappa,
      likelihood = "exal",
      inference = "vb_ld_tiny",
      seed = NA_integer_,
      status = if (converged) "prototype_success" else "prototype_max_iter"
    )
  )
  class(out) <- c("joint_qvp_qdesn_vb_fit", "list")
  out
}

app_joint_qvp_gamma_log_kernel <- function(gamma, y, fitted_no_alpha, alpha, sigma, s, v, tau, kappa) {
  constants <- tryCatch(app_joint_qvp_exal_constants(tau, gamma), error = function(e) NULL)
  if (is.null(constants)) return(-Inf)
  resid <- y - alpha - fitted_no_alpha - constants$lambda[[1L]] * sigma * s - constants$A[[1L]] * v
  val <- -0.5 * kappa * sum(log(constants$B[[1L]]) + resid^2 / (constants$B[[1L]] * sigma * v))
  if (is.finite(val)) val else -Inf
}

app_joint_qvp_gamma_to_eta <- function(gamma, lower, upper) {
  width <- upper - lower
  if (!is.finite(width) || width <= 0) stop("Invalid gamma support.", call. = FALSE)
  p <- (gamma - lower) / width
  p <- pmin(pmax(p, .Machine$double.eps), 1 - .Machine$double.eps)
  log(p) - log1p(-p)
}

app_joint_qvp_eta_to_gamma <- function(eta, lower, upper) {
  lower + (upper - lower) * stats::plogis(eta)
}

app_joint_qvp_gamma_logit_jacobian <- function(eta, lower, upper) {
  p <- stats::plogis(eta)
  log(upper - lower) + log(p) + log1p(-p)
}

app_joint_qvp_fit_exal_mcmc_tiny <- function(
  y,
  Z,
  tau,
  n_iter = 200L,
  burn = 100L,
  thin = 1L,
  seed = NULL,
  kappa = 1,
  tau0 = 1,
  zeta2 = Inf,
  gamma_init = NULL,
  init = NULL,
  alpha_min_spacing = 0,
  max_dense_dim = 250L,
  sigma_bounds = c(1.0e-8, 1.0e8),
  gamma_slice_width = NULL,
  gamma_slice_max_steps = 100L,
  gamma_update = c("bounded_slice", "logit_slice")
) {
  if (!is.null(seed)) set.seed(seed)
  gamma_update <- match.arg(gamma_update)
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Tn <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != Tn) stop("length(y) must match nrow(Z).", call. = FALSE)
  n_iter <- as.integer(n_iter)
  burn <- as.integer(burn)
  thin <- as.integer(thin)
  if (n_iter <= 0L || burn < 0L || burn >= n_iter || thin <= 0L) {
    stop("Invalid MCMC iteration, burn, or thin controls.", call. = FALSE)
  }
  if (!is.finite(kappa) || kappa <= 0) stop("kappa must be positive.", call. = FALSE)
  gamma_slice_max_steps <- as.integer(gamma_slice_max_steps)
  if (!length(gamma_slice_max_steps) || any(is.na(gamma_slice_max_steps)) ||
      any(gamma_slice_max_steps <= 0L)) {
    stop("gamma_slice_max_steps must be a positive integer scalar or vector.", call. = FALSE)
  }
  sigma_bounds <- as.numeric(sigma_bounds)
  if (length(sigma_bounds) != 2L || any(!is.finite(sigma_bounds)) ||
      sigma_bounds[[1L]] <= 0 || sigma_bounds[[2L]] <= sigma_bounds[[1L]]) {
    stop("sigma_bounds must be two increasing positive finite values.", call. = FALSE)
  }
  init <- app_joint_qvp_normalize_init(init, K, p)
  gamma <- init$gamma %||% if (is.null(gamma_init)) app_joint_qvp_default_gamma(tau) else app_joint_qvp_check_gamma(tau, gamma_init)
  support <- app_joint_qvp_exal_support(tau)
  beta <- init$beta %||% rep(0, K * p)
  alpha <- init$alpha %||% sort(as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8)))
  sigma <- init$sigma %||% rep(max(stats::mad(y), 1.0e-3), K)
  v <- matrix(rep(sigma, each = Tn), nrow = Tn, ncol = K)
  s <- matrix(abs(stats::rnorm(Tn * K)), nrow = Tn, ncol = K)
  rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = tau0, zeta2 = zeta2)
  keep_idx <- seq.int(burn + 1L, n_iter, by = thin)
  n_keep <- length(keep_idx)
  beta_draws <- matrix(NA_real_, nrow = n_keep, ncol = K * p)
  alpha_draws <- matrix(NA_real_, nrow = n_keep, ncol = K)
  sigma_draws <- matrix(NA_real_, nrow = n_keep, ncol = K)
  gamma_draws <- matrix(NA_real_, nrow = n_keep, ncol = K)
  keep_pos <- 0L
  for (iter in seq_len(n_iter)) {
    constants <- app_joint_qvp_exal_constants(tau, gamma)
    prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
    prior <- app_joint_qvp_build_prior_precision(K, p, prior_state$anchor, prior_state$innovations)
    work <- app_joint_qvp_build_working_response(
      y = y,
      Z = Z,
      beta = beta,
      alpha = alpha,
      tau = tau,
      sigma = sigma,
      v = v,
      kappa = kappa,
      likelihood = "exal",
      gamma = gamma,
      s = s
    )
    beta_update <- app_joint_qvp_beta_gaussian_update(work$Z_stack, work$y_star, work$weights, prior$P_beta)
    beta <- app_joint_qvp_precision_draw(beta_update$mean, beta_update$precision, max_dense_dim = max_dense_dim)
    rhs_state <- app_joint_qvp_update_rhs_state(rhs_state, beta, K, p)
    beta_mat <- app_joint_qvp_beta_matrix(beta, K, p)
    fitted_no_alpha <- Z %*% beta_mat
    for (k in seq_len(K)) {
      wk <- kappa / (constants$B[[k]] * sigma[[k]] * v[, k])
      resid_alpha <- y - fitted_no_alpha[, k] -
        constants$lambda[[k]] * sigma[[k]] * s[, k] -
        constants$A[[k]] * v[, k]
      prec <- sum(wk)
      mean <- sum(wk * resid_alpha) / prec
      lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + alpha_min_spacing
      upper <- if (k == K) Inf else alpha[[k + 1L]] - alpha_min_spacing
      if (lower >= upper) stop("Ordered intercept bounds collapsed.", call. = FALSE)
      alpha[[k]] <- app_joint_qvp_rtruncnorm(1, mean = mean, sd = sqrt(1 / prec), lower = lower, upper = upper)
    }
    fitted_no_alpha <- Z %*% beta_mat
    for (k in seq_len(K)) {
      r <- y - alpha[[k]] - fitted_no_alpha[, k]
      delta <- r - constants$lambda[[k]] * sigma[[k]] * s[, k]
      chi_v <- kappa * delta^2 / (constants$B[[k]] * sigma[[k]])
      psi_v <- kappa * (constants$A[[k]]^2 / (constants$B[[k]] * sigma[[k]]) + 2 / sigma[[k]])
      v[, k] <- app_joint_qvp_rgig(lambda = 1 - kappa / 2, chi = chi_v, psi = psi_v, current = v[, k])

      r0 <- r - constants$A[[k]] * v[, k]
      prec_s <- kappa * (1 + sigma[[k]] * constants$lambda[[k]]^2 / (constants$B[[k]] * v[, k]))
      mean_s <- constants$lambda[[k]] * r0 / (constants$B[[k]] * v[, k] + sigma[[k]] * constants$lambda[[k]]^2)
      s[, k] <- app_joint_qvp_rtruncnorm(Tn, mean = mean_s, sd = sqrt(1 / prec_s), lower = 0)

      chi_sigma <- 0.2 + 2 * kappa * sum(v[, k]) +
        kappa * sum((r - constants$A[[k]] * v[, k])^2 / (constants$B[[k]] * v[, k]))
      psi_sigma <- kappa * sum(constants$lambda[[k]]^2 * s[, k]^2 / (constants$B[[k]] * v[, k]))
      sigma[[k]] <- app_joint_qvp_rgig(
        lambda = -0.1 - 1.5 * kappa * Tn,
        chi = chi_sigma,
        psi = max(psi_sigma, .Machine$double.eps),
        current = sigma[[k]]
      )
      sigma[[k]] <- min(max(sigma[[k]], sigma_bounds[[1L]]), sigma_bounds[[2L]])

      gamma_width_default <- (support$upper[[k]] - support$lower[[k]]) / 20
      gamma_width <- if (is.null(gamma_slice_width)) {
        if (identical(gamma_update, "logit_slice")) 1 else gamma_width_default
      } else {
        gamma_slice_width <- as.numeric(gamma_slice_width)
        if (length(gamma_slice_width) == 1L) gamma_slice_width[[1L]] else gamma_slice_width[[k]]
      }
      gamma_steps <- if (length(gamma_slice_max_steps) == 1L) {
        gamma_slice_max_steps[[1L]]
      } else {
        gamma_slice_max_steps[[k]]
      }
      gamma_log_density <- function(g) {
        app_joint_qvp_gamma_log_kernel(
          gamma = g,
          y = y,
          fitted_no_alpha = fitted_no_alpha[, k],
          alpha = alpha[[k]],
          sigma = sigma[[k]],
          s = s[, k],
          v = v[, k],
          tau = tau[[k]],
          kappa = kappa
        )
      }
      if (identical(gamma_update, "logit_slice")) {
        support_lower <- support$lower[[k]]
        support_upper <- support$upper[[k]]
        margin <- max(1.0e-8, 1.0e-8 * (support_upper - support_lower))
        gamma_lower <- support_lower + margin
        gamma_upper <- support_upper - margin
        eta_lower <- app_joint_qvp_gamma_to_eta(gamma_lower, support_lower, support_upper)
        eta_upper <- app_joint_qvp_gamma_to_eta(gamma_upper, support_lower, support_upper)
        eta0 <- app_joint_qvp_gamma_to_eta(gamma[[k]], support_lower, support_upper)
        eta_new <- app_joint_qvp_slice_bounded_one(
          x0 = eta0,
          lower = eta_lower,
          upper = eta_upper,
          width = gamma_width,
          max_steps = gamma_steps,
          log_density = function(eta) {
            g <- app_joint_qvp_eta_to_gamma(eta, support_lower, support_upper)
            gamma_log_density(g) + app_joint_qvp_gamma_logit_jacobian(eta, support_lower, support_upper)
          }
        )
        gamma[[k]] <- app_joint_qvp_eta_to_gamma(eta_new, support_lower, support_upper)
      } else {
        gamma[[k]] <- app_joint_qvp_slice_bounded_one(
          x0 = gamma[[k]],
          lower = support$lower[[k]] + 1.0e-8,
          upper = support$upper[[k]] - 1.0e-8,
          width = gamma_width,
          max_steps = gamma_steps,
          log_density = gamma_log_density
        )
      }
    }
    if (iter %in% keep_idx) {
      keep_pos <- keep_pos + 1L
      beta_draws[keep_pos, ] <- beta
      alpha_draws[keep_pos, ] <- alpha
      sigma_draws[keep_pos, ] <- sigma
      gamma_draws[keep_pos, ] <- gamma
    }
  }
  beta_mean <- colMeans(beta_draws)
  alpha_mean <- colMeans(alpha_draws)
  qhat_mean <- Z %*% app_joint_qvp_beta_matrix(beta_mean, K, p) +
    matrix(alpha_mean, nrow = Tn, ncol = K, byrow = TRUE)
  out <- list(
    beta_draws = beta_draws,
    alpha_draws = alpha_draws,
    sigma_draws = sigma_draws,
    gamma_draws = gamma_draws,
    beta_mean = beta_mean,
    alpha_mean = alpha_mean,
    sigma_mean = colMeans(sigma_draws),
    gamma_mean = colMeans(gamma_draws),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    tau = tau,
    kappa = kappa,
    gamma_update = gamma_update,
    seed = seed,
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("joint_qvp_exal_mcmc_tiny_%s", format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau,
      kappa = kappa,
      likelihood = "exal",
      inference = "mcmc_tiny",
      seed = seed,
      status = "prototype_success"
    )
  )
  out$init_source <- if (is.null(init)) "default" else "provided"
  class(out) <- c("joint_qvp_qdesn_tiny_fit", "list")
  out
}
