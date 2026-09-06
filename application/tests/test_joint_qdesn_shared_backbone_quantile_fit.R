#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "..", "scripts", "_joint_qdesn_shared_backbone_quantile_bootstrap.R"))

contract <- app_joint_shared_quantile_read_contract()
stopifnot(
  contract$max_workers == 10L,
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  identical(contract$selection_policy, "observational_only_frozen_parent"),
  isTRUE(contract$protected_selection_forbidden)
)

plan <- app_joint_shared_quantile_job_plan(contract)
stopifnot(
  nrow(plan) == 51L,
  sum(plan$model_id == "gaussian_rhs_initializer") == 3L,
  sum(plan$model_id == "independent_qdesn_rhs") == 21L,
  sum(plan$model_id == "independent_exqdesn_rhs") == 21L,
  sum(plan$model_id == "joint_qdesn_rhs") == 3L,
  sum(plan$model_id == "joint_exqdesn_rhs") == 3L,
  identical(sort(unique(plan$stage_order)), 1:8)
)
for (ii in seq_len(nrow(plan))) {
  deps <- app_joint_shared_quantile_dependency_rows(plan, plan[ii, , drop = FALSE])
  stopifnot(!nrow(deps) || all(deps$stage_order < plan$stage_order[[ii]]))
}

set.seed(20260906)
Z <- cbind(x1 = stats::rnorm(28), x2 = stats::rnorm(28))
X <- cbind(`(Intercept)` = 1, Z)
y <- 0.4 + Z[, 1] - 0.25 * Z[, 2] + stats::rnorm(28, sd = 0.4)
ridge <- app_glofas_normal_ridge_fit(X, y)
candidate <- data.frame(candidate_id = "test", rhs_tau0 = 1, stringsAsFactors = FALSE)
design <- list(
  X = X, Z = Z, y = y, fit_local = seq_along(y),
  design_fingerprint = "test-design"
)
warm <- app_joint_shared_ridge_warm_start(ridge, candidate, design)
gaussian <- app_glofas_normal_rhs_fit(
  X, y, warm, tau0 = 1, max_iter = 8L, min_iter = 2L, tol = 1e-4
)
init <- app_joint_shared_quantile_gaussian_init(gaussian, design, contract$tau, contract)
stopifnot(
  length(init$beta_mean) == length(contract$tau) * ncol(Z),
  identical(dim(init$beta_cov), c(length(init$beta_mean), length(init$beta_mean))),
  length(init$alpha_mean) == length(contract$tau),
  all(diff(init$alpha_mean) > 0), all(is.finite(init$sigma_mean)), all(init$sigma_mean > 0),
  identical(init$source, "full_window_gaussian_rhs_vb")
)

al <- app_joint_qvp_fit_al_vb_tiny(
  y = y, Z = Z, tau = 0.5, max_iter = 3L, tol = 1e-5,
  tau0 = 1, a_sigma = 2, b_sigma = 1,
  alpha_prior_mean = init$alpha_mean[[4L]], alpha_prior_sd = init$alpha_prior_sd,
  max_dense_dim = 300L,
  init = list(
    beta_mean = init$beta_mean[7:8], beta_cov = init$beta_cov[7:8, 7:8, drop = FALSE],
    alpha_mean = init$alpha_mean[[4L]], sigma_mean = init$sigma_mean[[4L]],
    rhs_state = list(anchor = init$rhs_state$anchor), iterations_completed = 0L
  )
)
stopifnot(all(is.finite(c(al$beta_mean, al$alpha_mean, al$sigma_mean))))

exal <- app_joint_exqdesn_fit_vb_dispatch(
  method_id = contract$exal_vb_method,
  y = y, Z = Z, tau = 0.5, max_iter = 2L, tol = 1e-5,
  tau0 = 1, a_sigma = 2, b_sigma = 1,
  alpha_prior_mean = init$alpha_mean[[4L]], alpha_prior_sd = init$alpha_prior_sd,
  max_dense_dim = 300L, diagnostic_stride = 1L,
  quadrature_nodes = c(4L, 6L), quadrature_tolerance = 1e-4,
  init = app_joint_shared_quantile_reset_init(al)
)
stopifnot(
  identical(exal$inference_method_id, contract$exal_vb_method),
  all(is.finite(c(exal$beta_mean, exal$alpha_mean, exal$sigma_mean, exal$gamma_mean)))
)

joint_al <- app_joint_qvp_fit_al_vb_tiny(
  y = y, Z = Z, tau = contract$tau, max_iter = 1L, tol = 1e-5,
  tau0 = 1, a_sigma = 2, b_sigma = 1,
  alpha_prior_mean = init$alpha_mean, alpha_prior_sd = init$alpha_prior_sd,
  max_dense_dim = 300L, init = init
)
stopifnot(
  length(joint_al$alpha_mean) == length(contract$tau),
  all(is.finite(c(joint_al$beta_mean, joint_al$alpha_mean, joint_al$sigma_mean)))
)

qhat <- outer(seq(-1, 1, length.out = 12), contract$tau, function(x, tau) x + stats::qnorm(tau))
monotone <- app_joint_qdesn_apply_monotone_contract(qhat, contract$tau)
stopifnot(
  sum(monotone$raw_crossing$n_crossing_pairs) == 0L,
  sum(monotone$contract_crossing$n_crossing_pairs) == 0L,
  all(is.finite(app_joint_shared_weights(contract$tau))),
  abs(sum(app_joint_shared_weights(contract$tau)) - diff(range(contract$tau))) < 1e-12
)

cat("joint shared-backbone quantile continuation tests passed\n")
