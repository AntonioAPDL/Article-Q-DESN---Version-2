#!/usr/bin/env Rscript

file_arg <- sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))])
repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."), mustWork = TRUE)

source(file.path(repo_root, "application", "R", "00_packages.R"))
source(file.path(repo_root, "application", "R", "joint_qvp_qdesn.R"))
source(file.path(repo_root, "application", "R", "joint_exqdesn_exact_structured_inference.R"))

assert_close <- function(x, y, tolerance = 1.0e-8, label = "value") {
  delta <- max(abs(as.numeric(x) - as.numeric(y)))
  if (!is.finite(delta) || delta > tolerance) {
    stop(sprintf("%s continuation mismatch: %.12g", label, delta), call. = FALSE)
  }
}

set.seed(20260826)
n <- 19L
p <- 2L
tau <- c(0.2, 0.5, 0.8)
Z <- matrix(rnorm(n * p), nrow = n)
y <- 0.4 * Z[, 1L] - 0.2 * Z[, 2L] + rnorm(n, sd = 0.3)
common <- list(
  y = y, Z = Z, tau = tau, tol = 1.0e-30, tau0 = 0.01,
  a_sigma = 1, b_sigma = 1, max_dense_dim = 100L, rhs_vb_inner = 2L
)

al_full <- do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 5L)))
al_first <- do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 2L)))
al_resumed <- do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 3L, init = al_first)))
assert_close(al_full$beta_mean, al_resumed$beta_mean, label = "AL beta")
assert_close(al_full$beta_cov, al_resumed$beta_cov, label = "AL beta covariance")
assert_close(al_full$alpha_mean, al_resumed$alpha_mean, label = "AL alpha")
assert_close(al_full$sigma_rate, al_resumed$sigma_rate, label = "AL sigma rate")
assert_close(al_full$v_mean, al_resumed$v_mean, label = "AL latent mean")
stopifnot(isTRUE(all.equal(al_full$rhs_state, al_resumed$rhs_state, tolerance = 1.0e-8)))

# Use one common, explicit initializer so split and uninterrupted exAL runs begin
# from exactly the same state rather than their max_iter-dependent AL bootstrap.
exal_init <- do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 3L)))
exal_common <- c(common, list(
  augmentation = "v", init = exal_init, diagnostic_stride = 1L,
  quadrature_nodes = c(4L, 8L), quadrature_tolerance = 1.0e-6,
  method_id = "VB1_structured_v"
))
exal_full <- do.call(app_joint_exqdesn_fit_exal_vb_structured, modifyList(exal_common, list(max_iter = 3L)))
exal_first <- do.call(app_joint_exqdesn_fit_exal_vb_structured, modifyList(exal_common, list(max_iter = 1L)))
exal_resumed <- do.call(
  app_joint_exqdesn_fit_exal_vb_structured,
  modifyList(exal_common, list(max_iter = 2L, init = exal_first))
)
assert_close(exal_full$beta_mean, exal_resumed$beta_mean, label = "exAL beta")
assert_close(exal_full$beta_cov, exal_resumed$beta_cov, label = "exAL beta covariance")
assert_close(exal_full$alpha_mean, exal_resumed$alpha_mean, label = "exAL alpha")
assert_close(exal_full$sigma_mean, exal_resumed$sigma_mean, label = "exAL sigma")
assert_close(exal_full$gamma_mean, exal_resumed$gamma_mean, label = "exAL gamma")
assert_close(exal_full$v_mean, exal_resumed$v_mean, label = "exAL latent mean")
assert_close(exal_full$s_mean, exal_resumed$s_mean, label = "exAL half-normal mean")
stopifnot(isTRUE(all.equal(exal_full$rhs_state, exal_resumed$rhs_state, tolerance = 1.0e-8)))

bad_rhs <- al_first$rhs_state
bad_rhs$anchor$lambda2 <- bad_rhs$anchor$lambda2[-1L]
stopifnot(inherits(
  try(do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 1L, init = list(rhs_state = bad_rhs)))), silent = TRUE),
  "try-error"
))

cat("PriceFM joint continuation tests passed.\n")
