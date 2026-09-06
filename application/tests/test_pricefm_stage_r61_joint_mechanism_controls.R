#!/usr/bin/env Rscript

file_arg <- sub(
  "^--file=", "",
  commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]
)
repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."), mustWork = TRUE)

source(file.path(repo_root, "application", "R", "00_packages.R"))
source(file.path(repo_root, "application", "R", "joint_qvp_qdesn.R"))
source(file.path(repo_root, "application", "R", "joint_exqdesn_exact_structured_inference.R"))
source(file.path(repo_root, "application", "R", "pricefm_joint_quantile_inference.R"))

assert_close <- function(x, y, tolerance = 1.0e-8, label = "value") {
  delta <- max(abs(as.numeric(x) - as.numeric(y)))
  if (!is.finite(delta) || delta > tolerance) {
    stop(sprintf("%s mismatch: %.12g", label, delta), call. = FALSE)
  }
}

# Prior scales and initialization scales are separate scientific controls.
rhs <- app_joint_qvp_initialize_rhs_state(
  K = 3L,
  p = 2L,
  anchor_tau0 = 0.001,
  innovation_tau0 = 0.005,
  anchor_init_tau = 1,
  innovation_init_tau = 0.05
)
stopifnot(
  identical(names(rhs), c("anchor", "delta_2", "delta_3")),
  rhs$anchor$tau0 == 0.001,
  rhs$anchor$initial_tau == 1,
  sqrt(rhs$anchor$tau2) == 1,
  rhs$delta_2$tau0 == 0.005,
  rhs$delta_2$initial_tau == 0.05,
  sqrt(rhs$delta_2$tau2) == 0.05
)

set.seed(20260826)
n <- 17L
p <- 2L
tau <- c(0.2, 0.5, 0.8)
Z <- matrix(rnorm(n * p), nrow = n)
y <- 0.35 * Z[, 1L] - 0.15 * Z[, 2L] + rnorm(n, sd = 0.25)
common <- list(
  y = y,
  Z = Z,
  tau = tau,
  tol = 1.0e-30,
  anchor_tau0 = 0.001,
  innovation_tau0 = 0.005,
  anchor_init_tau = 1,
  innovation_init_tau = 0.05,
  a_sigma = 1,
  b_sigma = 1,
  max_dense_dim = 100L,
  rhs_vb_inner = 2L,
  rhs_freeze_iters = 2L
)

# Freeze decisions use the global iteration, including exact continuation.
al_full <- do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 5L)))
al_first <- do.call(app_joint_qvp_fit_al_vb_tiny, c(common, list(max_iter = 2L)))
al_resumed <- do.call(
  app_joint_qvp_fit_al_vb_tiny,
  c(common, list(max_iter = 3L, init = al_first))
)
assert_close(al_full$beta_mean, al_resumed$beta_mean, label = "AL beta continuation")
assert_close(al_full$beta_cov, al_resumed$beta_cov, label = "AL covariance continuation")
assert_close(al_full$alpha_mean, al_resumed$alpha_mean, label = "AL alpha continuation")
assert_close(al_full$sigma_rate, al_resumed$sigma_rate, label = "AL sigma continuation")
stopifnot(
  al_full$iterations_completed == 5L,
  al_resumed$iterations_completed == 5L,
  isTRUE(all.equal(al_full$rhs_state, al_resumed$rhs_state, tolerance = 1.0e-8))
)
anchor_trace <- al_full$rhs_diagnostics[al_full$rhs_diagnostics$block == "anchor", ]
stopifnot(
  identical(anchor_trace$global_iter, 1:5),
  all(!anchor_trace$rhs_update_performed[1:2]),
  all(anchor_trace$rhs_update_performed[3:5]),
  all(anchor_trace$rhs_freeze_active[1:2]),
  all(anchor_trace$tau[1:2] == 1),
  all(anchor_trace$tau0 == 0.001),
  all(anchor_trace$initial_tau == 1)
)

# The same controls are consumed by structured exAL, not retained as metadata.
exal_init <- do.call(
  app_joint_qvp_fit_al_vb_tiny,
  modifyList(common, list(max_iter = 1L, rhs_freeze_iters = 99L))
)
exal_init$iterations_completed <- 0L
exal <- do.call(
  app_joint_exqdesn_fit_exal_vb_structured,
  modifyList(common, list(
    max_iter = 2L,
    rhs_freeze_iters = 1L,
    init = exal_init,
    augmentation = "v",
    diagnostic_stride = 1L,
    quadrature_nodes = c(4L, 8L),
    quadrature_tolerance = 1.0e-6,
    method_id = "VB1_structured_v"
  ))
)
exal_anchor <- exal$rhs_diagnostics[exal$rhs_diagnostics$block == "anchor", ]
stopifnot(
  exal$iterations_completed == 2L,
  identical(exal_anchor$global_iter, 1:2),
  !exal_anchor$rhs_update_performed[[1L]],
  exal_anchor$rhs_update_performed[[2L]],
  exal_anchor$tau0[[1L]] == 0.001,
  exal_anchor$initial_tau[[1L]] == 1
)

# Training-only independent fits map to a joint initializer without using test.
fake_fit <- function(intercept, slopes, sigma, gamma, iter) {
  list(
    qbeta = list(m = c(intercept, slopes), V = diag(c(0.2, 0.1, 0.15))),
    qsiggam = list(sigma_mean = sigma, gamma_mean = gamma),
    converged = TRUE,
    iter = as.integer(iter)
  )
}
mapped <- app_pricefm_joint_independent_fits_to_init(
  fits = list(
    fake_fit(1, c(0.1, 0.2), 0.8, -0.2, 10L),
    fake_fit(0, c(0.3, 0.4), 0.9, 0.0, 11L),
    fake_fit(2, c(0.5, 0.6), 1.0, 0.2, 12L)
  ),
  tau = tau,
  n_features = 3L
)
assert_close(mapped$init$alpha_mean, c(0.5, 0.5, 2), label = "projected intercept")
assert_close(mapped$init$beta_mean, c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6), label = "mapped slopes")
stopifnot(
  identical(dim(mapped$init$beta_cov), c(6L, 6L)),
  mapped$init$iterations_completed == 0L,
  identical(mapped$init$gamma_mean, c(-0.2, 0, 0.2)),
  identical(mapped$diagnostics$intercept_projected, c(TRUE, TRUE, FALSE))
)

cat("PriceFM Stage-R61 joint mechanism control tests passed.\n")
