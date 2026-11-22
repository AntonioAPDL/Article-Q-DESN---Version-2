# Exact observation-space Gaussian ridge inference for p >= n designs.

app_joint_large_p_ridge_fit <- function(
  X,
  y,
  ridge_tau2 = 1.0e4,
  intercept_var = 1.0e6,
  sigma_a = 2.0,
  sigma_b = 1.0,
  jitter = 1.0e-8,
  max_jitter_tries = 6L
) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  n <- nrow(X)
  p <- ncol(X)
  if (!n || !p || any(!is.finite(X))) stop("X must be a finite nonempty matrix.", call. = FALSE)
  if (length(y) != n || any(!is.finite(y))) stop("y must match X and be finite.", call. = FALSE)
  ridge_tau2 <- as.numeric(ridge_tau2)
  intercept_var <- as.numeric(intercept_var)
  sigma_a <- as.numeric(sigma_a)
  sigma_b <- as.numeric(sigma_b)
  jitter <- as.numeric(jitter)
  max_jitter_tries <- as.integer(max_jitter_tries)
  if (!is.finite(ridge_tau2) || ridge_tau2 <= 0 ||
      !is.finite(intercept_var) || intercept_var <= 0) {
    stop("Ridge prior variances must be positive.", call. = FALSE)
  }
  if (!is.finite(sigma_a) || sigma_a <= 0 || !is.finite(sigma_b) || sigma_b <= 0) {
    stop("Sigma prior parameters must be positive.", call. = FALSE)
  }
  if (!is.finite(jitter) || jitter < 0 || max_jitter_tries < 1L) {
    stop("Invalid dual-ridge jitter controls.", call. = FALSE)
  }

  prior_variance <- rep(ridge_tau2, p)
  prior_variance[[1L]] <- intercept_var
  X_lambda <- sweep(X, 2L, prior_variance, "*")
  A <- diag(1, n) + tcrossprod(X_lambda, X)
  chol_A <- NULL
  jitter_used <- 0
  for (attempt in seq_len(max_jitter_tries)) {
    candidate <- A
    if (jitter_used > 0) diag(candidate) <- diag(candidate) + jitter_used
    chol_A <- tryCatch(chol(candidate), error = function(e) NULL)
    if (!is.null(chol_A)) break
    jitter_used <- if (jitter_used == 0) jitter else jitter_used * 10
  }
  if (is.null(chol_A)) stop("Dual ridge covariance factorization failed.", call. = FALSE)

  solve_A <- function(rhs) {
    backsolve(chol_A, forwardsolve(t(chol_A), rhs))
  }
  a_inv_y <- as.numeric(solve_A(y))
  beta_mean <- prior_variance * as.numeric(crossprod(X, a_inv_y))
  Xty <- as.numeric(crossprod(X, y))
  quad_post <- as.numeric(crossprod(beta_mean, Xty))
  sigma_a_post <- sigma_a + n / 2
  sigma_b_post <- max(
    sigma_b + 0.5 * (as.numeric(crossprod(y)) - quad_post),
    .Machine$double.eps
  )
  sigma2_mean <- if (sigma_a_post > 1) {
    sigma_b_post / (sigma_a_post - 1)
  } else {
    sigma_b_post / sigma_a_post
  }

  # If A = R'R, solve R'C = X Lambda. Then diag(P^-1) is
  # diag(Lambda) - colSums(C^2), without constructing P^-1.
  C <- forwardsolve(t(chol_A), X_lambda)
  precision_inv_diag <- pmax(prior_variance - colSums(C * C), 0)
  beta_var_diag <- sigma2_mean * precision_inv_diag
  if (any(!is.finite(beta_mean)) || any(!is.finite(beta_var_diag))) {
    stop("Dual ridge returned non-finite posterior moments.", call. = FALSE)
  }

  list(
    beta_mean = beta_mean,
    beta_cov = NULL,
    beta_var_diag = beta_var_diag,
    precision = NULL,
    precision_chol = NULL,
    precision_inv = NULL,
    sigma_a = sigma_a_post,
    sigma_b = sigma_b_post,
    sigma2_mean = sigma2_mean,
    ridge_tau2 = ridge_tau2,
    intercept_var = intercept_var,
    n_train = n,
    p = p,
    covariance_representation = "dual_woodbury_exact",
    dual_chol = chol_A,
    dual_training_design = X,
    dual_prior_variance = prior_variance,
    dual_jitter_used = jitter_used,
    materialized_parameter_covariance = FALSE
  )
}

app_joint_large_p_ridge_param_var <- function(fit, X_new) {
  X_new <- as.matrix(X_new)
  storage.mode(X_new) <- "double"
  if (!identical(as.character(fit$covariance_representation %||% ""),
      "dual_woodbury_exact")) {
    stop("Expected an exact dual-Woodbury ridge fit.", call. = FALSE)
  }
  X <- as.matrix(fit$dual_training_design)
  prior_variance <- as.numeric(fit$dual_prior_variance)
  chol_A <- as.matrix(fit$dual_chol)
  if (ncol(X_new) != ncol(X) || length(prior_variance) != ncol(X) ||
      !all(dim(chol_A) == c(nrow(X), nrow(X)))) {
    stop("Dual ridge prediction representation is malformed.", call. = FALSE)
  }
  X_new_lambda <- sweep(X_new, 2L, prior_variance, "*")
  prior_quad <- rowSums(X_new_lambda * X_new)
  cross_term <- X_new_lambda %*% t(X)
  solved <- forwardsolve(t(chol_A), t(cross_term))
  posterior_quad <- pmax(prior_quad - colSums(solved * solved), 0)
  as.numeric(fit$sigma2_mean) * posterior_quad
}

app_joint_large_p_ridge_predict <- function(fit, X_new) {
  X_new <- as.matrix(X_new)
  if (ncol(X_new) != fit$p) stop("Prediction design has wrong column count.", call. = FALSE)
  mu <- as.numeric(X_new %*% fit$beta_mean)
  param_var <- app_joint_large_p_ridge_param_var(fit, X_new)
  sigma2 <- as.numeric(fit$sigma2_mean)
  sd <- sqrt(pmax(sigma2 + param_var, .Machine$double.eps))
  list(mean = mu, sd = sd, leverage = param_var / max(sigma2, .Machine$double.eps))
}

app_joint_ridge_fit_dispatch <- function(
  X,
  y,
  ridge_tau2 = 1.0e4,
  intercept_var = 1.0e6,
  sigma_a = 2.0,
  sigma_b = 1.0,
  backend = c("auto", "primal", "dual")
) {
  backend <- match.arg(backend)
  if (identical(backend, "auto")) backend <- if (ncol(X) >= nrow(X)) "dual" else "primal"
  if (identical(backend, "dual")) {
    return(app_joint_large_p_ridge_fit(
      X, y, ridge_tau2 = ridge_tau2, intercept_var = intercept_var,
      sigma_a = sigma_a, sigma_b = sigma_b
    ))
  }
  fit <- app_glofas_normal_ridge_fit(
    X, y, ridge_tau2 = ridge_tau2, intercept_var = intercept_var,
    sigma_a = sigma_a, sigma_b = sigma_b
  )
  fit$covariance_representation <- "primal_dense_exact"
  fit$materialized_parameter_covariance <- TRUE
  fit
}

app_joint_ridge_predict_dispatch <- function(fit, X_new, chunk_size = NULL) {
  if (identical(as.character(fit$covariance_representation %||% ""),
      "dual_woodbury_exact")) {
    return(app_joint_large_p_ridge_predict(fit, X_new))
  }
  app_glofas_normal_predict(fit, X_new, chunk_size = chunk_size)
}
