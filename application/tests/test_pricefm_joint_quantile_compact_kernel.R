#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]), "..", ".."), mustWork = FALSE)
file_arg <- sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))])
if (length(file_arg)) repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."), mustWork = TRUE)

source(file.path(repo_root, "application", "R", "00_packages.R"))
source(file.path(repo_root, "application", "R", "joint_qvp_qdesn.R"))
source(file.path(repo_root, "application", "R", "pricefm_joint_quantile_inference.R"))

set.seed(20260824)
n <- 31L
p <- 4L
tau <- c(0.1, 0.5, 0.9)
K <- length(tau)
Z <- matrix(rnorm(n * p), nrow = n)
y <- rnorm(n)
beta <- rnorm(K * p, sd = 0.2)
alpha <- c(-0.5, 0, 0.5)
sigma <- c(0.8, 1.0, 1.2)
v <- matrix(rexp(n * K) + 0.1, nrow = n)

prior <- app_joint_qvp_build_prior_precision(
  K = K,
  p = p,
  anchor = list(lambda2 = rep(1, p), tau2 = 0.2, zeta2 = Inf),
  innovations = replicate(K - 1L, list(lambda2 = rep(1, p), tau2 = 0.3, zeta2 = Inf), simplify = FALSE)
)
dense_work <- app_joint_qvp_build_working_response(
  y = y, Z = Z, beta = beta, alpha = alpha, tau = tau,
  sigma = sigma, v = v, likelihood = "al"
)
compact_work <- app_pricefm_joint_build_working_response_compact(
  y = y, Z = Z, beta = beta, alpha = alpha, tau = tau,
  sigma = sigma, v = v, likelihood = "al"
)
stopifnot(max(abs(dense_work$y_star - compact_work$y_star)) < 1.0e-12)
stopifnot(max(abs(dense_work$weights - compact_work$weights)) < 1.0e-12)
stopifnot(max(abs(dense_work$qhat - compact_work$qhat)) < 1.0e-12)

dense_update <- app_joint_qvp_beta_gaussian_update(
  dense_work$Z_stack, dense_work$y_star, dense_work$weights, prior$P_beta
)
compact_update <- app_pricefm_joint_beta_gaussian_update_compact(
  compact_work$Z_stack, compact_work$y_star, compact_work$weights,
  prior$P_beta, chunk_size = 7L
)
stopifnot(max(abs(as.matrix(dense_update$precision) - as.matrix(compact_update$precision))) < 1.0e-9)
stopifnot(max(abs(dense_update$mean - compact_update$mean)) < 1.0e-9)
stopifnot(max(abs(as.numeric(Matrix::t(dense_work$Z_stack) %*% (dense_work$weights * dense_work$y_star)) - compact_update$rhs)) < 1.0e-9)
stopifnot(identical(compact_update$backend, "pricefm_compact_block_crossproduct_v1"))

X <- cbind(1, Z)
pred <- app_pricefm_joint_predict(X, beta, alpha, tau)
expected <- Z %*% app_joint_qvp_beta_matrix(beta, K, p) + matrix(alpha, n, K, byrow = TRUE)
stopifnot(max(abs(pred - expected)) < 1.0e-12)
bad_X <- X
bad_X[1L, 1L] <- 0
stopifnot(inherits(try(app_pricefm_joint_strip_intercept(bad_X), silent = TRUE), "try-error"))

restore <- app_pricefm_joint_install_compact_mcmc_kernel(chunk_size = 9L)
stopifnot(app_pricefm_joint_is_compact_design(
  app_joint_qvp_build_working_response(
    y = y, Z = Z, beta = beta, alpha = alpha, tau = tau,
    sigma = sigma, v = v, likelihood = "al"
  )$Z_stack
))
restore()
stopifnot(inherits(
  app_joint_qvp_build_working_response(
    y = y, Z = Z, beta = beta, alpha = alpha, tau = tau,
    sigma = sigma, v = v, likelihood = "al"
  )$Z_stack,
  "sparseMatrix"
))

cat("PriceFM compact joint-quantile kernel tests passed.\n")
