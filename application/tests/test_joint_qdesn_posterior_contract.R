#!/usr/bin/env Rscript

if (!exists("app_joint_posterior_contract", mode = "function") ||
    !exists("app_joint_article_overdispersed_start", mode = "function")) {
  file_arg <- sub(
    "^--file=", "",
    commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]
  )
  repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."), mustWork = TRUE)
  source(file.path(repo_root, "application", "scripts",
    "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))
}

tau <- c(0.05, 0.25, 0.50, 0.75, 0.95)
alpha_mean <- stats::qnorm(tau)
alpha_sd <- rep(2.5, length(tau))

stopifnot(identical(app_joint_qvp_validate_sigma_bounds(c(0, Inf)), c(0, Inf)))
for (invalid in list(c(-1, Inf), c(0, 0), c(0, NA), c(1), c(0, -Inf))) {
  stopifnot(inherits(try(app_joint_qvp_validate_sigma_bounds(invalid),
    silent = TRUE), "try-error"))
}

target_1 <- app_joint_posterior_contract(
  likelihood_family = "exAL", fit_structure = "joint", tau = tau,
  design_fingerprint = "fixture-design-sha256", tau0 = 0.1, zeta2 = 1,
  slab_fixed = TRUE,
  a_sigma = 2, b_sigma = 1, alpha_prior_mean = alpha_mean,
  alpha_prior_sd = alpha_sd, alpha_min_spacing = 1e-8,
  sigma_bounds = c(0, Inf)
)
target_2 <- app_joint_posterior_contract(
  likelihood_family = "exAL", fit_structure = "joint", tau = tau,
  design_fingerprint = "fixture-design-sha256", tau0 = 0.1, zeta2 = 1,
  slab_fixed = TRUE,
  a_sigma = 2, b_sigma = 1, alpha_prior_mean = alpha_mean,
  alpha_prior_sd = alpha_sd, alpha_min_spacing = 1e-8,
  sigma_bounds = c(0, Inf)
)
stopifnot(
  identical(target_1$hash, target_2$hash),
  identical(app_joint_posterior_assert_identical(list(target_1, target_2)),
    target_1$hash),
  identical(target_1$sigma_bounds, c(0, Inf)),
  target_1$zeta2 == 1,
  isTRUE(target_1$slab_fixed)
)

changed_prior <- target_2
changed_prior$hash <- app_joint_posterior_contract(
  likelihood_family = "exAL", fit_structure = "joint", tau = tau,
  design_fingerprint = "fixture-design-sha256", tau0 = 0.1, zeta2 = 1,
  slab_fixed = TRUE,
  a_sigma = 2, b_sigma = 1, alpha_prior_mean = alpha_mean + 0.01,
  alpha_prior_sd = alpha_sd, alpha_min_spacing = 1e-8,
  sigma_bounds = c(0, Inf)
)$hash
stopifnot(inherits(try(app_joint_posterior_assert_identical(
  list(target_1, changed_prior)), silent = TRUE), "try-error"))

base_init <- list(
  beta_mean = rep(0.1, length(tau) * 2L),
  alpha_mean = alpha_mean,
  sigma_mean = rep(1, length(tau)),
  gamma_mean = rep(0, length(tau))
)
job_1 <- data.frame(chain_start_seed = 202609091L)
job_2 <- data.frame(chain_start_seed = 202609092L)
start_1 <- app_joint_article_overdispersed_start(base_init, job_1, tau)
start_2 <- app_joint_article_overdispersed_start(base_init, job_2, tau)
stopifnot(
  !identical(start_1$beta_mean, start_2$beta_mean),
  !identical(start_1$alpha_mean, start_2$alpha_mean),
  identical(target_1$hash, target_2$hash)
)
stopifnot(inherits(try(app_joint_posterior_assert_initialization_only(
  c(base_init, list(alpha_prior_mean = alpha_mean))), silent = TRUE),
  "try-error"))

# Resolve the same target from one frozen Gaussian initializer for two chains.
root <- tempfile("joint_target_contract_")
dir.create(file.path(root, "workers", "worker_0001"), recursive = TRUE)
app_write_csv(data.frame(
  job_id = 1L, scenario_id = "normal", model_id = "gaussian_rhs_initializer",
  tau = NA_real_, stringsAsFactors = FALSE
), file.path(root, "vb_worker_plan.csv"))
gaussian <- list(
  rhs_tau0 = 0.1,
  initializer = list(
    zeta2 = 1,
    alpha_mean = alpha_mean,
    alpha_prior_sd = alpha_sd[[1L]]
  )
)
saveRDS(gaussian, file.path(root, "workers", "worker_0001",
  "fit_initializer.rds"))
contract <- list(
  a_sigma = 2, b_sigma = 1, alpha_min_spacing = 1e-8,
  rhs_slab_variance = 1,
  sigma_lower_bound = 0, sigma_upper_bound = Inf,
  coefficient_hierarchy = "first_quantile_anchor_adjacent_differences",
  rhs_slab_fixed = TRUE,
  ordered_intercepts = TRUE,
  primary_score = "dgp_integrated_finite_grid_acrps",
  projection_rule = "weighted_isotonic_equal_weights",
  draw_coupling = "matched_draw_index_with_repeated_permutation_sensitivity"
)
design <- list(
  tau = tau,
  design_fingerprint = "fixture-design-sha256",
  posterior_data_design_fingerprint = "fixture-response-design-sha256",
  y = seq_along(tau), Z = matrix(seq_along(tau), ncol = 1L),
  fit_local = seq_along(tau)
)
model_job <- data.frame(
  scenario_id = "normal", likelihood_family = "exAL",
  fit_structure = "joint", rhs_tau0 = 0.1, chain_id = c(1L, 2L),
  stringsAsFactors = FALSE
)
resolved <- lapply(seq_len(nrow(model_job)), function(i) {
  app_joint_article_resolve_posterior_target(root,
    model_job[i, , drop = FALSE], design, contract)
})
stopifnot(identical(app_joint_posterior_assert_identical(resolved),
  resolved[[1L]]$hash), resolved[[1L]]$zeta2 == 1,
  isTRUE(resolved[[1L]]$slab_fixed))
independent_job <- model_job[1L, , drop = FALSE]
independent_job$fit_structure <- "independent"
independent_target <- app_joint_article_resolve_posterior_target(
  root, independent_job, design, contract)
stopifnot(identical(independent_target$coefficient_hierarchy,
  "independent_quantile_specific_rhs"),
  !isTRUE(independent_target$ordered_intercepts))

# Every chain in a model cell must carry the same immutable target hash.
hash_summary <- data.frame(
  model_cell_id = rep(c("cell_a", "cell_b"), each = 2L),
  likelihood_family = rep(c("AL", "exAL"), each = 2L),
  posterior_target_sha256 = rep(c(target_1$hash, target_2$hash), each = 2L),
  stringsAsFactors = FALSE
)
hash_contract <- list(
  posterior_target_hash_required = TRUE,
  expected_top_level_initializers = 2L,
  al_chains_per_cell = 2L,
  exal_chains_per_cell = 2L
)
hash_audit <- app_joint_article_target_hash_audit(hash_summary, hash_contract)
stopifnot(nrow(hash_audit) == 2L, all(hash_audit$verified))
bad_hash_summary <- hash_summary
bad_hash_summary$posterior_target_sha256[[2L]] <- changed_prior$hash
stopifnot(inherits(try(app_joint_article_target_hash_audit(
  bad_hash_summary, hash_contract), silent = TRUE), "try-error"))

# Positive, unbounded sigma support is accepted without a start-derived cap.
set.seed(20260909L)
y <- stats::rnorm(24L)
Z <- matrix(stats::rnorm(24L), ncol = 1L)
al_fit <- app_joint_qvp_fit_al_mcmc_tiny(
  y = y, Z = Z, tau = 0.5, n_iter = 16L, burn = 8L,
  thin = 1L, seed = 20260909L, tau0 = 0.1, zeta2 = 1,
  slab_fixed = TRUE,
  a_sigma = 2, b_sigma = 1, alpha_prior_mean = 0,
  alpha_prior_sd = 2.5, sigma_bounds = c(0, Inf)
)
stopifnot(
  identical(al_fit$sigma_bounds, c(0, Inf)),
  all(is.finite(al_fit$sigma_draws)),
  all(al_fit$sigma_draws > 0)
)

fixed_slab <- app_joint_qvp_initialize_rhs_state(
  K = 2L, p = 2L, tau0 = 0.1, zeta2 = 1, slab_fixed = TRUE)
set.seed(20260909L)
fixed_slab_mcmc <- app_joint_qvp_update_rhs_state(
  fixed_slab, beta = c(0.1, -0.2, 0.3, -0.1), K = 2L, p = 2L)
fixed_slab_vb <- app_joint_qvp_update_rhs_vb_state(
  fixed_slab, beta_mean = c(0.1, -0.2, 0.3, -0.1),
  beta_cov = diag(4L) * 0.01, K = 2L, p = 2L, n_inner = 2L)$state
stopifnot(
  all(vapply(fixed_slab_mcmc, function(x) x$zeta2 == 1, logical(1L))),
  all(vapply(fixed_slab_vb, function(x) x$zeta2 == 1, logical(1L))),
  all(vapply(fixed_slab_vb, function(x) isTRUE(x$slab_fixed), logical(1L)))
)

cat("JOINT posterior-target contract tests passed.\n")
