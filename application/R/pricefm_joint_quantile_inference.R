# PriceFM-scoped compact linear algebra for the joint quantile application.

app_pricefm_joint_require_core <- function() {
  required <- c(
    "app_joint_qvp_check_design",
    "app_joint_qvp_validate_tau_grid",
    "app_joint_qvp_beta_matrix",
    "app_joint_qvp_al_constants",
    "app_joint_qvp_exal_constants"
  )
  missing <- required[!vapply(required, exists, logical(1L), mode = "function", inherits = TRUE)]
  if (length(missing)) {
    stop(
      sprintf("Load application/R/joint_qvp_qdesn.R before this module: %s", paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_pricefm_joint_compact_design <- function(Z, K) {
  Z <- app_joint_qvp_check_design(Z)
  K <- as.integer(K)
  if (length(K) != 1L || is.na(K) || K < 1L) stop("K must be a positive integer.", call. = FALSE)
  structure(
    list(Z = Z, K = K, n = nrow(Z), p = ncol(Z)),
    class = c("pricefm_joint_compact_design", "list")
  )
}

app_pricefm_joint_is_compact_design <- function(x) {
  inherits(x, "pricefm_joint_compact_design")
}

app_pricefm_joint_strip_intercept <- function(X, tolerance = 1.0e-10) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  if (!nrow(X) || ncol(X) < 2L || any(!is.finite(X))) {
    stop("PriceFM design must be a finite matrix with an intercept and at least one slope.", call. = FALSE)
  }
  max_error <- max(abs(X[, 1L] - 1))
  if (!is.finite(max_error) || max_error > tolerance) {
    stop("PriceFM adapter column 1 is not the required constant intercept.", call. = FALSE)
  }
  Z <- X[, -1L, drop = FALSE]
  attr(Z, "removed_intercept_max_error") <- max_error
  Z
}

app_pricefm_joint_weighted_crossproducts <- function(Z, y_star, weights, chunk_size = 2048L) {
  Z <- app_joint_qvp_check_design(Z)
  y_star <- as.numeric(y_star)
  weights <- as.numeric(weights)
  n <- nrow(Z)
  p <- ncol(Z)
  chunk_size <- as.integer(chunk_size)
  if (length(y_star) != n || length(weights) != n) {
    stop("Compact weighted crossproducts require one response and weight per design row.", call. = FALSE)
  }
  if (chunk_size < 1L || any(!is.finite(y_star)) || any(!is.finite(weights)) || any(weights <= 0)) {
    stop("Invalid compact weighted-crossproduct inputs.", call. = FALSE)
  }
  precision <- matrix(0, nrow = p, ncol = p)
  rhs <- numeric(p)
  starts <- seq.int(1L, n, by = chunk_size)
  for (start in starts) {
    end <- min(n, start + chunk_size - 1L)
    idx <- start:end
    Z_chunk <- Z[idx, , drop = FALSE]
    sqrt_w <- sqrt(weights[idx])
    weighted_Z <- Z_chunk * sqrt_w
    precision <- precision + crossprod(weighted_Z)
    rhs <- rhs + as.numeric(crossprod(Z_chunk, weights[idx] * y_star[idx]))
  }
  list(precision = precision, rhs = rhs, chunks = length(starts))
}

app_pricefm_joint_beta_gaussian_update_compact <- function(
  compact_design,
  y_star,
  weights,
  P_beta,
  chunk_size = 2048L
) {
  app_pricefm_joint_require_core()
  if (!app_pricefm_joint_is_compact_design(compact_design)) {
    stop("compact_design must come from app_pricefm_joint_compact_design().", call. = FALSE)
  }
  app_require_namespace("Matrix")
  Z <- compact_design$Z
  K <- compact_design$K
  n <- compact_design$n
  p <- compact_design$p
  y_star <- as.numeric(y_star)
  weights <- as.numeric(weights)
  if (length(y_star) != n * K || length(weights) != n * K) {
    stop("Stacked working vectors do not match the compact design dimensions.", call. = FALSE)
  }
  blocks <- vector("list", K)
  rhs <- numeric(K * p)
  n_chunks <- 0L
  for (k in seq_len(K)) {
    row_idx <- ((k - 1L) * n + 1L):(k * n)
    beta_idx <- ((k - 1L) * p + 1L):(k * p)
    cross <- app_pricefm_joint_weighted_crossproducts(
      Z = Z,
      y_star = y_star[row_idx],
      weights = weights[row_idx],
      chunk_size = chunk_size
    )
    blocks[[k]] <- Matrix::Matrix(cross$precision, sparse = TRUE)
    rhs[beta_idx] <- cross$rhs
    n_chunks <- n_chunks + cross$chunks
  }
  precision <- Matrix::forceSymmetric(Matrix::bdiag(blocks) + P_beta)
  mean <- as.numeric(Matrix::solve(precision, rhs))
  list(
    precision = precision,
    mean = mean,
    rhs = rhs,
    backend = "pricefm_compact_block_crossproduct_v1",
    chunk_size = as.integer(chunk_size),
    crossproduct_chunks = n_chunks
  )
}

app_pricefm_joint_build_working_response_compact <- function(
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
  app_pricefm_joint_require_core()
  likelihood <- match.arg(likelihood)
  y <- as.numeric(y)
  Z <- app_joint_qvp_check_design(Z)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  n <- length(y)
  K <- length(tau)
  p <- ncol(Z)
  if (nrow(Z) != n) stop("length(y) must match nrow(Z).", call. = FALSE)
  alpha <- as.numeric(alpha)
  sigma <- as.numeric(sigma)
  if (length(alpha) != K || length(sigma) != K || any(!is.finite(sigma)) || any(sigma <= 0)) {
    stop("alpha and positive sigma must have length K.", call. = FALSE)
  }
  if (!is.finite(kappa) || kappa <= 0) stop("kappa must be positive.", call. = FALSE)
  v <- as.matrix(v)
  storage.mode(v) <- "double"
  if (!identical(dim(v), c(n, K)) || any(!is.finite(v)) || any(v <= 0)) {
    stop("v must be a positive length(y)-by-K matrix.", call. = FALSE)
  }
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
    if (!identical(dim(s), c(n, K)) || any(!is.finite(s)) || any(s < 0)) {
      stop("s must be a nonnegative length(y)-by-K matrix.", call. = FALSE)
    }
  } else {
    s <- matrix(0, nrow = n, ncol = K)
  }
  y_star <- numeric(n * K)
  weights <- numeric(n * K)
  qhat <- Z %*% beta_mat
  for (k in seq_len(K)) {
    idx <- ((k - 1L) * n + 1L):(k * n)
    y_star[idx] <- y - alpha[[k]] -
      constants$lambda[[k]] * sigma[[k]] * s[, k] -
      constants$A[[k]] * v[, k]
    weights[idx] <- kappa / (constants$B[[k]] * sigma[[k]] * v[, k])
  }
  list(
    y_star = y_star,
    weights = weights,
    Z_stack = app_pricefm_joint_compact_design(Z, K),
    qhat = qhat + matrix(alpha, nrow = n, ncol = K, byrow = TRUE),
    constants = constants,
    kappa = kappa,
    likelihood = likelihood,
    backend = "pricefm_compact_working_response_v1"
  )
}

app_pricefm_joint_install_compact_mcmc_kernel <- function(chunk_size = 2048L) {
  app_pricefm_joint_require_core()
  target_env <- environment(app_joint_qvp_build_working_response)
  old_working <- get("app_joint_qvp_build_working_response", envir = target_env, inherits = FALSE)
  old_update <- get("app_joint_qvp_beta_gaussian_update", envir = target_env, inherits = FALSE)
  compact_update <- function(Z_stack, y_star, weights, P_beta) {
    if (!app_pricefm_joint_is_compact_design(Z_stack)) {
      return(old_update(Z_stack, y_star, weights, P_beta))
    }
    app_pricefm_joint_beta_gaussian_update_compact(
      compact_design = Z_stack,
      y_star = y_star,
      weights = weights,
      P_beta = P_beta,
      chunk_size = chunk_size
    )
  }
  assign("app_joint_qvp_build_working_response", app_pricefm_joint_build_working_response_compact, envir = target_env)
  assign("app_joint_qvp_beta_gaussian_update", compact_update, envir = target_env)
  restored <- FALSE
  function() {
    if (!restored) {
      assign("app_joint_qvp_build_working_response", old_working, envir = target_env)
      assign("app_joint_qvp_beta_gaussian_update", old_update, envir = target_env)
      restored <<- TRUE
    }
    invisible(TRUE)
  }
}

app_pricefm_joint_predict <- function(X, beta, alpha, tau, intercept_tolerance = 1.0e-10) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  Z <- app_pricefm_joint_strip_intercept(X, tolerance = intercept_tolerance)
  p <- ncol(Z)
  K <- length(tau)
  alpha <- as.numeric(alpha)
  if (length(beta) != K * p || length(alpha) != K) {
    stop("Joint coefficient or intercept dimensions do not match X and tau.", call. = FALSE)
  }
  Z %*% app_joint_qvp_beta_matrix(beta, K, p) + matrix(alpha, nrow(Z), K, byrow = TRUE)
}
