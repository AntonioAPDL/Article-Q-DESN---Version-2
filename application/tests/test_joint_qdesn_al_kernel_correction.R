#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."))
source(file.path(repo_root,
  "application/scripts/_joint_qdesn_stronger_window_bootstrap.R"))
source(file.path(repo_root, "application/R/rhs_global_scale_reference.R"))

# The AL scale conditional is inverse-gamma on (0, Inf), with no clipping.
resid <- c(-1.2, 0.4, 2.1, -0.3)
v <- c(0.5, 1.2, 0.8, 2.0)
A <- -0.75
B <- 3.5
kappa <- 0.8
a_sigma <- 2.2
b_sigma <- 1.1
conditional <- app_joint_qvp_al_sigma_conditional(
  resid, v, A, B, kappa, a_sigma, b_sigma)
expected_shape <- a_sigma + 1.5 * kappa * length(resid)
expected_rate <- b_sigma + kappa * (
  sum(v) + 0.5 * sum((resid - A * v)^2 / (B * v)))
stopifnot(
  identical(conditional$support, c(0, Inf)),
  identical(conditional$update_id, "direct_inverse_gamma_unbounded_v1"),
  isTRUE(all.equal(conditional$shape, expected_shape, tolerance = 0)),
  isTRUE(all.equal(conditional$rate, expected_rate, tolerance = 0))
)

set.seed(2026112301L)
expected_draw <- app_joint_qvp_rinvgamma(1L, expected_shape, expected_rate)
set.seed(2026112301L)
observed_draw <- app_joint_qvp_draw_al_sigma(
  resid, v, A, B, kappa, a_sigma, b_sigma)$value
stopifnot(identical(observed_draw, expected_draw))

# Historical finite cap arguments are compatibility inputs only. They cannot
# change the target support or create a clipped transition.
stopifnot(
  identical(app_joint_qvp_al_sigma_support(c(0, Inf)), c(0, Inf)),
  identical(app_joint_qvp_al_sigma_support(c(1e-8, 2)), c(0, Inf))
)

set.seed(2026112302L)
y <- stats::rnorm(20L)
Z <- matrix(stats::rnorm(20L), ncol = 1L)
fit_low <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y, Z = Z, tau = 0.5, n_iter = 12L, burn = 6L, thin = 1L,
  seed = 2026112303L, a_sigma = 2, b_sigma = 1,
  sigma_bounds = c(1e-8, 0.2), init = list(sigma_mean = 0.1))
fit_high <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y, Z = Z, tau = 0.5, n_iter = 12L, burn = 6L, thin = 1L,
  seed = 2026112303L, a_sigma = 2, b_sigma = 1,
  sigma_bounds = c(1e-8, 1e6), init = list(sigma_mean = 10))
stopifnot(
  identical(fit_low$sigma_bounds, c(0, Inf)),
  identical(fit_high$sigma_bounds, c(0, Inf)),
  identical(fit_low$sigma_update_id, "direct_inverse_gamma_unbounded_v1"),
  identical(fit_high$sigma_update_id, "direct_inverse_gamma_unbounded_v1"),
  all(is.finite(fit_low$sigma_draws)), all(fit_low$sigma_draws > 0),
  all(is.finite(fit_high$sigma_draws)), all(fit_high$sigma_draws > 0)
)

design <- list(
  tau = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
  posterior_data_design_fingerprint = paste(rep("a", 64L), collapse = ""))
normal <- list(initializer = list(
  zeta2 = 1,
  alpha_mean = stats::qnorm(design$tau),
  alpha_prior_sd = 2.5))
target_al <- app_joint_swcf_complete_target(
  "joint_qdesn_rhs", design, normal, tau0 = 0.1)
target_exal <- app_joint_swcf_complete_target(
  "joint_exqdesn_rhs", design, normal, tau0 = 0.1)
kernel_al <- app_joint_swcf_sampler_control_contract(
  "joint_qdesn_rhs", n_iter = 2000L, burn = 500L, thin = 2L)
kernel_al_repeat <- app_joint_swcf_sampler_control_contract(
  "joint_qdesn_rhs", n_iter = 2000L, burn = 500L, thin = 2L)
kernel_al_changed <- app_joint_swcf_sampler_control_contract(
  "joint_qdesn_rhs", n_iter = 2002L, burn = 500L, thin = 2L)
stopifnot(
  identical(target_al$sigma_bounds, c(0, Inf)),
  !identical(target_al$hash, target_exal$hash),
  identical(kernel_al$hash, kernel_al_repeat$hash),
  !identical(kernel_al$hash, kernel_al_changed$hash)
)

# Numerical starts do not enter either immutable identity.
start_a <- app_joint_article_overdispersed_start(
  list(beta_mean = rep(0, 7L), alpha_mean = normal$initializer$alpha_mean,
    sigma_mean = rep(0.1, 7L)),
  data.frame(chain_start_seed = 202611231L), design$tau)
start_b <- app_joint_article_overdispersed_start(
  list(beta_mean = rep(0, 7L), alpha_mean = normal$initializer$alpha_mean,
    sigma_mean = rep(10, 7L)),
  data.frame(chain_start_seed = 202611232L), design$tau)
stopifnot(
  !identical(start_a$sigma_mean, start_b$sigma_mean),
  identical(target_al$hash, app_joint_swcf_complete_target(
    "joint_qdesn_rhs", design, normal, tau0 = 0.1)$hash),
  identical(kernel_al$hash, app_joint_swcf_sampler_control_contract(
    "joint_qdesn_rhs", 2000L, 500L, 2L)$hash)
)

# Compatible chains combine; either target or kernel drift fails closed.
summary <- data.frame(
  model_cell_id = rep("cell_a", 3L),
  model_id = rep("joint_qdesn_rhs", 3L),
  likelihood_family = rep("AL", 3L),
  complete_posterior_target_sha256 = rep(target_al$hash, 3L),
  effective_sampler_control_sha256 = rep(kernel_al$hash, 3L),
  stringsAsFactors = FALSE)
audit <- app_joint_swcf_chain_identity_audit(summary, expected_chains = 3L)
stopifnot(nrow(audit) == 1L, isTRUE(audit$verified[[1L]]))
bad_target <- summary
bad_target$complete_posterior_target_sha256[[3L]] <- target_exal$hash
bad_kernel <- summary
bad_kernel$effective_sampler_control_sha256[[2L]] <- kernel_al_changed$hash
stopifnot(
  inherits(try(app_joint_swcf_chain_identity_audit(
    bad_target, 3L), silent = TRUE), "try-error"),
  inherits(try(app_joint_swcf_chain_identity_audit(
    bad_kernel, 3L), silent = TRUE), "try-error")
)

block <- list(
  posterior_target_sha256 = target_al$hash,
  complete_posterior_target_sha256 = target_al$hash,
  effective_sampler_control_sha256 = kernel_al$hash)
combined_identity <- app_joint_superfinal_combined_identity(
  list(block, block, block))
stopifnot(
  identical(combined_identity$complete_posterior_target_sha256,
    target_al$hash),
  identical(combined_identity$effective_sampler_control_sha256,
    kernel_al$hash))
bad_block <- block
bad_block$effective_sampler_control_sha256 <- kernel_al_changed$hash
stopifnot(inherits(try(app_joint_superfinal_combined_identity(
  list(block, bad_block)), silent = TRUE), "try-error"))

# Fallback is a complete scenario decision, never a favorable-row splice.
models <- c("independent_qdesn_rhs", "joint_qdesn_rhs",
  "independent_exqdesn_rhs", "joint_exqdesn_rhs")
mcmc <- expand.grid(
  scenario_id = "persistent_heavy_tail",
  specification_role = c("new_geometry_parity", "challenger"),
  model_id = models,
  stringsAsFactors = FALSE)
challenger <- app_joint_superfinal_whole_scenario_packet(
  mcmc, "persistent_heavy_tail", TRUE)
parity <- app_joint_superfinal_whole_scenario_packet(
  mcmc, "persistent_heavy_tail", FALSE)
stopifnot(
  nrow(challenger) == 4L,
  all(challenger$specification_role == "challenger"),
  all(challenger$promote_complete_challenger_packet),
  nrow(parity) == 4L,
  all(parity$specification_role == "new_geometry_parity"),
  !any(parity$promote_complete_challenger_packet)
)

# Exact-M0 exAL remains the default and is outside the corrected AL branch.
stopifnot(identical(app_joint_exqdesn_default_method_id("mcmc"),
  "M0_v_collapsed_support_logit"))
rhs_reference <- app_rhs_reference_tau0(
  m0 = 5, r = 100, n_fit = 400, sigma_ref = 2)
rhs_al <- app_rhs_reference_tau0_al(
  m0 = 5, r = 100, n_fit = 400, p0 = 0.25, sigma_ref = 2)
stopifnot(
  abs(rhs_reference - (5 / 95) * (2 / 20)) < 1e-15,
  abs(rhs_al - app_rhs_reference_tau0(
    m0 = 5, r = 100, n_fit = 400, sigma_ref = 2,
    information_factor = 0.25 * 0.75)) < 1e-15)

cat("JOINT AL kernel-correction tests passed.\n")
