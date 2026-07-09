tau <- app_joint_qvp_validate_tau_grid(c(0.1, 0.5, 0.9))
stopifnot(identical(tau, c(0.1, 0.5, 0.9)))

bad_tau <- try(app_joint_qvp_validate_tau_grid(c(0.5, 0.1)), silent = TRUE)
stopifnot(inherits(bad_tau, "try-error"))

dup_tau <- try(app_joint_qvp_validate_tau_grid(c(0.1, 0.1)), silent = TRUE)
stopifnot(inherits(dup_tau, "try-error"))

H1 <- app_joint_qvp_build_difference_matrix(K = 1L, p = 3L)
stopifnot(identical(dim(H1), c(3L, 3L)))
stopifnot(all(as.matrix(H1) == diag(3)))

H <- app_joint_qvp_build_difference_matrix(K = 3L, p = 2L)
beta <- c(1, 2, 4, 8, 16, 32)
eta <- app_joint_qvp_apply_difference(beta, K = 3L, p = 2L)
stopifnot(identical(eta, c(1, 2, 3, 6, 12, 24)))

Z <- matrix(c(1, 2, 3, 4, 5, 6), nrow = 3L, ncol = 2L)
Zs <- app_joint_qvp_build_stacked_design(Z, K = 3L)
stopifnot(identical(dim(Zs), c(9L, 6L)))
stopifnot(all(as.matrix(Zs)[1:3, 1:2] == Z))
stopifnot(all(as.matrix(Zs)[4:6, 3:4] == Z))
stopifnot(all(as.matrix(Zs)[7:9, 5:6] == Z))
stopifnot(sum(as.matrix(Zs)[1:3, 3:6]) == 0)

prior <- app_joint_qvp_build_prior_precision(
  K = 3L,
  p = 2L,
  anchor = list(lambda2 = c(1, 2), tau2 = 4, zeta2 = 16),
  innovations = list(lambda2 = c(2, 4), tau2 = 9, zeta2 = Inf)
)
P_dense <- as.matrix(prior$P_beta)
P_ref <- t(as.matrix(H)) %*% as.matrix(prior$P_delta) %*% as.matrix(H)
stopifnot(max(abs(P_dense - P_ref)) < 1.0e-12)
stopifnot(max(abs(P_dense - t(P_dense))) < 1.0e-12)
stopifnot(all(eigen(P_dense, symmetric = TRUE, only.values = TRUE)$values > 0))

beta_cov <- diag(0.1, 6L)
eta_moments <- app_joint_qvp_difference_moments(beta, beta_cov, K = 3L, p = 2L)
stopifnot(length(eta_moments$mean) == 6L)
stopifnot(length(eta_moments$second) == 6L)
stopifnot(all(eta_moments$second >= eta_moments$mean^2))

rhs_state <- app_joint_qvp_initialize_rhs_state(K = 3L, p = 2L, tau0 = 1)
rhs_update <- app_joint_qvp_update_rhs_vb_state(rhs_state, beta, beta_cov, K = 3L, p = 2L)
rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_update$state, K = 3L, p = 2L)
stopifnot(identical(rhs_summary$block, c("anchor", "delta_2", "delta_3")))
stopifnot(all(is.finite(rhs_summary$mean_precision)))
stopifnot(all(rhs_summary$mean_precision > 0))
stopifnot(any(abs(rhs_summary$mean_precision - 1) > 1.0e-8))
rhs_elbo_terms <- app_joint_qvp_rhs_vb_elbo_terms(rhs_update$state, K = 3L, p = 2L)
stopifnot(nrow(rhs_elbo_terms) == 9L)
stopifnot(identical(unique(rhs_elbo_terms$block), c("anchor", "delta_2", "delta_3")))
stopifnot(all(c(
  "expected_log_rhs_scale_prior_kernel",
  "q_rhs_scale_entropy",
  "expected_log_beta_prior_log_precision_approx"
) %in% rhs_elbo_terms$term))
stopifnot(all(is.finite(rhs_elbo_terms$value)))
stopifnot(any(rhs_elbo_terms$status == "included_log_precision_mean_field_approximation"))

gig_lambda <- 0.7
gig_chi <- 1.2
gig_psi <- 2.4
gig_log_integral <- app_joint_qvp_gig_log_integral(gig_lambda, gig_chi, gig_psi)
gig_log_integral_numeric <- app_joint_qvp_gig_log_integral_numeric_one(gig_lambda, gig_chi, gig_psi)
stopifnot(abs(gig_log_integral - gig_log_integral_numeric) < 1.0e-7)
stopifnot(abs(app_joint_qvp_gig_moment(gig_lambda, gig_chi, gig_psi, 0) - 1) < 1.0e-10)
gig_log_mean <- app_joint_qvp_gig_log_moment(gig_lambda, gig_chi, gig_psi)
gig_entropy <- app_joint_qvp_gig_entropy(gig_lambda, gig_chi, gig_psi)
stopifnot(is.finite(gig_log_mean))
stopifnot(is.finite(gig_entropy))

large_order_gig <- expand.grid(
  lambda = c(-750.1, -1500, 750.1),
  chi = c(1.0e-12, 1, 1.0e12),
  psi = c(1.0e-12, 1, 1.0e12),
  r = c(-1, 1),
  KEEP.OUT.ATTRS = FALSE
)
large_order_moments <- vapply(seq_len(nrow(large_order_gig)), function(ii) {
  row <- large_order_gig[ii, , drop = FALSE]
  app_joint_qvp_gig_moment(row$lambda, row$chi, row$psi, row$r)
}, numeric(1L))
stopifnot(all(is.finite(large_order_moments)))
stopifnot(all(large_order_moments > 0))

y <- c(1, 3, 5)
alpha <- c(0, 1, 2)
sigma <- c(1, 1.5, 2)
v <- matrix(1, nrow = 3L, ncol = 3L)
work <- app_joint_qvp_build_working_response(
  y = y,
  Z = Z,
  beta = beta,
  alpha = alpha,
  tau = tau,
  sigma = sigma,
  v = v,
  kappa = 1 / 3,
  likelihood = "al"
)
const <- app_joint_qvp_al_constants(tau)
stopifnot(length(work$y_star) == 9L)
stopifnot(length(work$weights) == 9L)
stopifnot(abs(work$weights[[1L]] - (1 / 3) / (const$B[[1L]] * sigma[[1L]])) < 1.0e-12)

beta_update <- app_joint_qvp_beta_gaussian_update(work$Z_stack, work$y_star, work$weights, prior$P_beta)
stopifnot(length(beta_update$mean) == 6L)
stopifnot(all(is.finite(beta_update$mean)))

set.seed(42L)
sparse_draw <- app_joint_qvp_precision_draw(
  mean = rep(0, 6L),
  precision = beta_update$precision,
  max_dense_dim = 0L,
  force_sparse = TRUE
)
stopifnot(length(sparse_draw) == 6L)
stopifnot(all(is.finite(sparse_draw)))
fac <- Matrix::Cholesky(Matrix::forceSymmetric(beta_update$precision), LDL = FALSE, perm = TRUE)
expanded <- Matrix::expand(fac)
reconstructed_precision <- Matrix::t(expanded$P) %*% expanded$L %*% Matrix::t(expanded$L) %*% expanded$P
stopifnot(max(abs(as.matrix(beta_update$precision - reconstructed_precision))) < 1.0e-8)

q_cross <- matrix(c(1, 2, 3, 1, 0, 2), nrow = 2L, byrow = TRUE)
diag_cross <- app_joint_qvp_crossing_diagnostics(q_cross, tau)
stopifnot(diag_cross$n_crossing_pairs[[1L]] == 0L)
stopifnot(diag_cross$n_crossing_pairs[[2L]] == 1L)

manifest <- app_joint_qvp_manifest_row(
  fit_id = "toy",
  tau = tau,
  kappa = 1 / 3,
  likelihood = "al",
  inference = "algebra",
  seed = 123L
)
stopifnot(identical(manifest$fit_id[[1L]], "toy"))
stopifnot(identical(manifest$likelihood[[1L]], "al"))
stopifnot(abs(manifest$kappa[[1L]] - 1 / 3) < 1.0e-12)

exal <- app_joint_qvp_exal_constants(c(0.5), gamma = 0)
al <- app_joint_qvp_al_constants(c(0.5))
stopifnot(abs(exal$A[[1L]] - al$A[[1L]]) < 1.0e-12)
stopifnot(abs(exal$B[[1L]] - al$B[[1L]]) < 1.0e-12)
stopifnot(abs(exal$lambda[[1L]]) < 1.0e-12)
