#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_stronger_window_bootstrap.R"))

set.seed(20261121L)
n <- 60L
p <- 24L
X <- cbind(`(Intercept)` = 1, matrix(stats::rnorm(n * (p - 1L)), n, p - 1L))
y <- as.numeric(X %*% seq(-0.3, 0.3, length.out = p) + stats::rnorm(n, sd = 0.7))
primal <- app_glofas_normal_ridge_fit(X, y, ridge_tau2 = 20, intercept_var = 500,
  sigma_a = 2.5, sigma_b = 1.2)
dual <- app_joint_large_p_ridge_fit(X, y, ridge_tau2 = 20, intercept_var = 500,
  sigma_a = 2.5, sigma_b = 1.2)
stopifnot(
  max(abs(primal$beta_mean - dual$beta_mean)) < 1e-9,
  abs(primal$sigma_a - dual$sigma_a) < 1e-12,
  abs(primal$sigma_b - dual$sigma_b) < 1e-9,
  max(abs(primal$beta_var_diag - dual$beta_var_diag)) < 1e-8,
  is.null(dual$beta_cov),
  is.null(dual$precision_inv),
  !dual$materialized_parameter_covariance
)

X_new <- cbind(`(Intercept)` = 1, matrix(stats::rnorm(11L * (p - 1L)), 11L, p - 1L))
pred_primal <- app_glofas_normal_predict(primal, X_new)
pred_dual <- app_joint_large_p_ridge_predict(dual, X_new)
stopifnot(
  max(abs(pred_primal$mean - pred_dual$mean)) < 1e-9,
  max(abs(pred_primal$sd - pred_dual$sd)) < 1e-8,
  max(abs(pred_primal$leverage - pred_dual$leverage)) < 1e-8
)

set.seed(20261122L)
X_wide <- cbind(`(Intercept)` = 1, matrix(stats::rnorm(30L * 79L), 30L, 79L))
y_wide <- stats::rnorm(30L)
wide <- app_joint_ridge_fit_dispatch(X_wide, y_wide, backend = "auto")
wide_pred <- app_joint_ridge_predict_dispatch(wide, X_wide[1:4, , drop = FALSE])
stopifnot(
  identical(wide$covariance_representation, "dual_woodbury_exact"),
  !wide$materialized_parameter_covariance,
  length(wide$beta_var_diag) == ncol(X_wide),
  all(is.finite(wide_pred$mean)),
  all(is.finite(wide_pred$sd)),
  all(wide_pred$sd > 0)
)

candidate <- data.frame(candidate_id = "dual_unit", stringsAsFactors = FALSE)
design <- list(X = X_wide)
colnames(design$X) <- paste0("x", seq_len(ncol(design$X)))
warm <- app_joint_shared_ridge_warm_start(wide, candidate, design)
app_glofas_normal_part1_validate_ridge_warm_start(warm, strict_hash = FALSE)

cat("Large-p exact dual ridge tests passed.\n")
